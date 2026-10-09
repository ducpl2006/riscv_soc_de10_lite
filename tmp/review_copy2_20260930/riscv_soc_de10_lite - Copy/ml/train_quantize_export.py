#!/usr/bin/env python3
"""Huấn luyện và xuất FFNN INT8 cho accelerator SOC 80-16-8-1.

Đặc tả dữ liệu và số học:
  * Nguồn: CALCE INR18650-20R, 12 ZIP động lực học, mỗi ZIP có file 50/80 SOC.
  * Split theo profile: DST+FUDS=train, US06=validation, BJDST=test.
  * Một mẫu gồm 20 thời điểm x [mV, mA, 0.1 degC, delta-ms] = 80 phần tử.
  * Nhãn SOC được coulomb-count từ SOC đầu file với dung lượng danh định 2 Ah.
  * Trọng số INT8, bias/accumulator INT32, ReLU và dịch phải đúng RTL.

Script cố ý không dùng TensorFlow. Mạng nhỏ được huấn luyện bằng NumPy/Adam để
giữ môi trường nhẹ, dễ khóa phiên bản và dễ kiểm tra từng phép toán.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import random
import re
import shutil
import sys
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
from openpyxl import load_workbook


SEQUENCE_LENGTH = 20
FEATURE_COUNT = 4
INPUT_COUNT = SEQUENCE_LENGTH * FEATURE_COUNT
L1_COUNT = 16
L2_COUNT = 8
SAMPLE_PERIOD_S = 10.0
RATED_CAPACITY_AH = 2.0
FEATURE_NAMES = ("voltage_mv", "current_ma", "temperature_deci_c", "delta_ms")
TRAIN_PROFILES = {"DST", "FUDS"}
VALIDATION_PROFILES = {"US06"}
TEST_PROFILES = {"BJDST"}


@dataclass(frozen=True)
class SeriesInfo:
    archive: str
    member: str
    profile: str
    ambient_c: int
    initial_soc: int
    measured_capacity_ah: float
    raw_rows: int
    resampled_rows: int
    soc_min: float
    soc_max: float


@dataclass
class FloatModel:
    w1: np.ndarray
    b1: np.ndarray
    w2: np.ndarray
    b2: np.ndarray
    w3: np.ndarray
    b3: np.ndarray


@dataclass
class QuantModel:
    w1: np.ndarray
    b1: np.ndarray
    w2: np.ndarray
    b2: np.ndarray
    w3: np.ndarray
    b3: np.ndarray
    l1_shift: int
    l2_shift: int
    out_shift: int
    l1_fraction_bits: int
    l1_activation_fraction_bits: int
    l2_fraction_bits: int
    l2_activation_fraction_bits: int
    out_fraction_bits: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--learning-rate", type=float, default=1.0e-3)
    parser.add_argument("--seed", type=int, default=20250920)
    parser.add_argument("--train-stride", type=int, default=5)
    parser.add_argument("--eval-stride", type=int, default=1)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--max-install-rmse", type=float, default=5.0)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def read_expected_hashes(path: Path) -> dict[str, str]:
    expected: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        digest, name = line.split(maxsplit=1)
        expected[name] = digest.upper()
    return expected


def verify_archives(raw_dir: Path, sums_path: Path) -> list[Path]:
    expected = read_expected_hashes(sums_path)
    actual_names = {path.name for path in raw_dir.glob("*.zip")}
    if actual_names != set(expected):
        missing = sorted(set(expected) - actual_names)
        extra = sorted(actual_names - set(expected))
        raise RuntimeError(f"Sai tập archive. Thiếu={missing}; dư={extra}")
    archives: list[Path] = []
    for name in sorted(expected):
        path = raw_dir / name
        actual = sha256(path)
        if actual != expected[name]:
            raise RuntimeError(f"SHA256 sai cho {name}: {actual}")
        with zipfile.ZipFile(path) as archive:
            members = [item for item in archive.namelist() if not item.endswith("/")]
            if len(members) != 2:
                raise RuntimeError(f"{name} phải có đúng 2 file, hiện có {len(members)}")
        archives.append(path)
    return archives


def parse_archive_metadata(archive_name: str, member_name: str) -> tuple[str, int, int]:
    archive_match = re.fullmatch(r"SP2_(0C|25C|45C)_(DST|FUDS|US06|BJDST)\.zip", archive_name)
    soc_match = re.search(r"_(50|80)SOC\.xls$", member_name, flags=re.IGNORECASE)
    if archive_match is None or soc_match is None:
        raise RuntimeError(f"Tên dữ liệu không đúng contract: {archive_name}/{member_name}")
    ambient_c = int(archive_match.group(1)[:-1])
    return archive_match.group(2), ambient_c, int(soc_match.group(1))


def load_measurements(
    blob: bytes, source: str, initial_soc: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray, float]:
    workbook = load_workbook(io.BytesIO(blob), read_only=True, data_only=True)
    try:
        required = {
            "Test_Time(s)",
            "Current(A)",
            "Voltage(V)",
            "Step_Index",
            "Charge_Capacity(Ah)",
        }
        candidates: list[tuple[object, tuple[object, ...]]] = []
        for name in workbook.sheetnames:
            if not name.startswith("Channel_") or name == "Channel_Chart":
                continue
            candidate = workbook[name]
            candidate_header = tuple(
                next(candidate.iter_rows(min_row=1, max_row=1, values_only=True))
            )
            if required.issubset(set(candidate_header)):
                candidates.append((candidate, candidate_header))
        if len(candidates) != 1:
            names = [getattr(item[0], "title", "?") for item in candidates]
            raise RuntimeError(
                f"{source}: cần đúng một sheet đo có {sorted(required)}, thấy {names}"
            )
        sheet, header = candidates[0]
        time_col = header.index("Test_Time(s)")
        current_col = header.index("Current(A)")
        voltage_col = header.index("Voltage(V)")
        step_col = header.index("Step_Index")
        charge_capacity_col = header.index("Charge_Capacity(Ah)")
        times: list[float] = []
        currents: list[float] = []
        voltages: list[float] = []
        steps: list[int] = []
        charge_capacities: list[float] = []
        max_col = max(
            time_col, current_col, voltage_col, step_col, charge_capacity_col
        ) + 1
        for row in sheet.iter_rows(min_row=2, max_col=max_col, values_only=True):
            values = (
                row[time_col],
                row[current_col],
                row[voltage_col],
                row[step_col],
                row[charge_capacity_col],
            )
            if any(value is None for value in values):
                continue
            try:
                t, current, voltage, step, charge_capacity = map(float, values)
            except (TypeError, ValueError):
                continue
            if math.isfinite(t) and math.isfinite(current) and math.isfinite(voltage):
                times.append(t)
                currents.append(current)
                voltages.append(voltage)
                steps.append(int(step))
                charge_capacities.append(charge_capacity)
    finally:
        workbook.close()

    time_array = np.asarray(times, dtype=np.float64)
    current_array = np.asarray(currents, dtype=np.float64)
    voltage_array = np.asarray(voltages, dtype=np.float64)
    step_array = np.asarray(steps, dtype=np.int32)
    charge_capacity_array = np.asarray(charge_capacities, dtype=np.float64)
    if time_array.size < SEQUENCE_LENGTH:
        raise RuntimeError(f"{source}: chỉ có {time_array.size} dòng hợp lệ")
    dynamic_indices = np.flatnonzero(step_array == 7)
    if dynamic_indices.size == 0:
        raise RuntimeError(f"{source}: không tìm thấy Step_Index=7 của profile động")
    dynamic_start = int(dynamic_indices[0])
    selected_time = time_array[dynamic_start:]
    selected_current = current_array[dynamic_start:]
    net_dynamic_ah = float(
        np.sum(
            0.5
            * (selected_current[:-1] + selected_current[1:])
            * np.diff(selected_time)
            / 3600.0
        )
    )
    measured_capacity_ah = -net_dynamic_ah / (initial_soc / 100.0)
    if not 1.0 <= measured_capacity_ah <= 3.0:
        raise RuntimeError(
            f"{source}: dung lượng đo {measured_capacity_ah:.6f} Ah ngoài miền hợp lệ"
        )
    time_array = time_array[dynamic_start:]
    current_array = current_array[dynamic_start:]
    voltage_array = voltage_array[dynamic_start:]
    keep = np.concatenate(([True], np.diff(time_array) > 0.0))
    return (
        time_array[keep],
        current_array[keep],
        voltage_array[keep],
        measured_capacity_ah,
    )


def resample_series(
    time_s: np.ndarray,
    current_a: np.ndarray,
    voltage_v: np.ndarray,
    ambient_c: int,
    initial_soc: int,
    measured_capacity_ah: float,
) -> tuple[np.ndarray, np.ndarray]:
    delta_t = np.diff(time_s)
    delta_ah = 0.5 * (current_a[:-1] + current_a[1:]) * delta_t / 3600.0
    soc = np.empty_like(time_s)
    soc[0] = float(initial_soc)
    soc[1:] = initial_soc + np.cumsum(delta_ah) * (100.0 / measured_capacity_ah)
    soc = np.clip(soc, 0.0, 100.0)

    start = math.ceil(time_s[0] / SAMPLE_PERIOD_S) * SAMPLE_PERIOD_S
    stop = math.floor(time_s[-1] / SAMPLE_PERIOD_S) * SAMPLE_PERIOD_S
    grid = np.arange(start, stop + 0.5 * SAMPLE_PERIOD_S, SAMPLE_PERIOD_S)
    if grid.size < SEQUENCE_LENGTH:
        raise RuntimeError("Chuỗi sau resample ngắn hơn cửa sổ 20 mẫu")
    voltage_mv = np.rint(np.interp(grid, time_s, voltage_v) * 1000.0)
    current_ma = np.rint(np.interp(grid, time_s, current_a) * 1000.0)
    temperature_deci_c = np.full(grid.shape, ambient_c * 10.0)
    delta_ms = np.full(grid.shape, SAMPLE_PERIOD_S * 1000.0)
    features = np.column_stack((voltage_mv, current_ma, temperature_deci_c, delta_ms))
    labels = np.interp(grid, time_s, soc) * 10.0
    return features.astype(np.int32), labels.astype(np.float32)


def make_windows(features: np.ndarray, labels: np.ndarray, stride: int) -> tuple[np.ndarray, np.ndarray]:
    if stride < 1:
        raise ValueError("stride phải >= 1")
    view = np.lib.stride_tricks.sliding_window_view(
        features, window_shape=SEQUENCE_LENGTH, axis=0
    )
    # NumPy trả [window_start, feature, time]; chuyển về [time, feature].
    windows = view.transpose(0, 2, 1)[::stride]
    targets = labels[SEQUENCE_LENGTH - 1 :: stride]
    return windows.reshape(windows.shape[0], INPUT_COUNT).copy(), targets.reshape(-1, 1).copy()


def load_dataset(
    archives: Sequence[Path], train_stride: int, eval_stride: int
) -> tuple[dict[str, tuple[np.ndarray, np.ndarray]], list[SeriesInfo]]:
    split_x: dict[str, list[np.ndarray]] = {"train": [], "validation": [], "test": []}
    split_y: dict[str, list[np.ndarray]] = {"train": [], "validation": [], "test": []}
    infos: list[SeriesInfo] = []
    for archive_path in archives:
        with zipfile.ZipFile(archive_path) as archive:
            for member in sorted(archive.namelist()):
                if member.endswith("/"):
                    continue
                profile, ambient_c, initial_soc = parse_archive_metadata(archive_path.name, member)
                source = f"{archive_path.name}/{member}"
                time_s, current_a, voltage_v, measured_capacity_ah = load_measurements(
                    archive.read(member), source, initial_soc
                )
                features, labels = resample_series(
                    time_s,
                    current_a,
                    voltage_v,
                    ambient_c,
                    initial_soc,
                    measured_capacity_ah,
                )
                if profile in TRAIN_PROFILES:
                    split = "train"
                    stride = train_stride
                elif profile in VALIDATION_PROFILES:
                    split = "validation"
                    stride = eval_stride
                elif profile in TEST_PROFILES:
                    split = "test"
                    stride = eval_stride
                else:
                    raise AssertionError(profile)
                windows, targets = make_windows(features, labels, stride)
                split_x[split].append(windows)
                split_y[split].append(targets)
                infos.append(
                    SeriesInfo(
                        archive=archive_path.name,
                        member=member,
                        profile=profile,
                        ambient_c=ambient_c,
                        initial_soc=initial_soc,
                        measured_capacity_ah=measured_capacity_ah,
                        raw_rows=int(time_s.size),
                        resampled_rows=int(features.shape[0]),
                        soc_min=float(labels.min() / 10.0),
                        soc_max=float(labels.max() / 10.0),
                    )
                )
                print(
                    f"DATA {split:10s} {source}: raw={time_s.size}, "
                    f"resampled={features.shape[0]}, windows={windows.shape[0]}"
                )
    result: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    for split in ("train", "validation", "test"):
        result[split] = (np.concatenate(split_x[split]), np.concatenate(split_y[split]))
    return result, infos


def derive_feature_quantization(train_x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    samples = train_x.reshape(-1, FEATURE_COUNT).astype(np.float64)
    lower = np.percentile(samples, 0.1, axis=0)
    upper = np.percentile(samples, 99.9, axis=0)
    center = np.rint((lower + upper) * 0.5).astype(np.int32)
    max_distance = np.maximum(np.abs(lower - center), np.abs(upper - center))
    scale = np.maximum(1, np.ceil(max_distance / 127.0)).astype(np.int32)
    # delta-ms là contract thời gian, không phải tín hiệu học. 10 s phải lượng tử về 0.
    center[3] = int(SAMPLE_PERIOD_S * 1000.0)
    scale[3] = 1
    return center, scale


def quantize_features(raw_x: np.ndarray, center: np.ndarray, scale: np.ndarray) -> np.ndarray:
    shaped = raw_x.reshape(-1, SEQUENCE_LENGTH, FEATURE_COUNT).astype(np.int64)
    # C/C++ integer division cắt về 0; np.trunc tái tạo đúng cho số âm.
    quantized = np.trunc((shaped - center) / scale)
    return np.clip(quantized, -128, 127).astype(np.int8).reshape(-1, INPUT_COUNT)


def initialize_model(rng: np.random.Generator) -> FloatModel:
    def he(fan_in: int, fan_out: int) -> np.ndarray:
        return (rng.standard_normal((fan_in, fan_out)) * math.sqrt(2.0 / fan_in)).astype(np.float32)

    return FloatModel(
        w1=he(INPUT_COUNT, L1_COUNT),
        b1=np.zeros(L1_COUNT, dtype=np.float32),
        w2=he(L1_COUNT, L2_COUNT),
        b2=np.zeros(L2_COUNT, dtype=np.float32),
        w3=he(L2_COUNT, 1),
        b3=np.zeros(1, dtype=np.float32),
    )


def forward_train(model: FloatModel, x: np.ndarray) -> tuple[np.ndarray, tuple[np.ndarray, ...]]:
    z1 = x @ model.w1 + model.b1
    a1 = np.maximum(z1, 0.0)
    z2 = a1 @ model.w2 + model.b2
    a2 = np.maximum(z2, 0.0)
    output = a2 @ model.w3 + model.b3
    return output, (x, z1, a1, z2, a2)


def model_arrays(model: FloatModel) -> list[np.ndarray]:
    return [model.w1, model.b1, model.w2, model.b2, model.w3, model.b3]


def evaluate_float_training(model: FloatModel, x: np.ndarray, y: np.ndarray, batch_size: int = 4096) -> float:
    squared_sum = 0.0
    count = 0
    for start in range(0, x.shape[0], batch_size):
        prediction, _ = forward_train(model, x[start : start + batch_size])
        error = prediction - y[start : start + batch_size]
        squared_sum += float(np.sum(error.astype(np.float64) ** 2))
        count += error.size
    return math.sqrt(squared_sum / count)


def train_model(
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_validation: np.ndarray,
    y_validation: np.ndarray,
    epochs: int,
    batch_size: int,
    learning_rate: float,
    rng: np.random.Generator,
) -> tuple[FloatModel, list[dict[str, float]]]:
    model = initialize_model(rng)
    parameters = model_arrays(model)
    first_moment = [np.zeros_like(value) for value in parameters]
    second_moment = [np.zeros_like(value) for value in parameters]
    beta1, beta2, epsilon = 0.9, 0.999, 1.0e-7
    step = 0
    best_rmse = math.inf
    best_parameters = [value.copy() for value in parameters]
    patience = 10
    epochs_without_improvement = 0
    history: list[dict[str, float]] = []

    for epoch in range(1, epochs + 1):
        permutation = rng.permutation(x_train.shape[0])
        epoch_loss = 0.0
        seen = 0
        for start in range(0, x_train.shape[0], batch_size):
            indices = permutation[start : start + batch_size]
            xb = x_train[indices]
            yb = y_train[indices]
            prediction, cache = forward_train(model, xb)
            x, z1, a1, z2, a2 = cache
            error = prediction - yb
            batch_count = xb.shape[0]
            epoch_loss += float(np.sum(error.astype(np.float64) ** 2))
            seen += batch_count

            d_output = (2.0 / batch_count) * error
            grad_w3 = a2.T @ d_output
            grad_b3 = d_output.sum(axis=0)
            d_a2 = d_output @ model.w3.T
            d_z2 = d_a2 * (z2 > 0.0)
            grad_w2 = a1.T @ d_z2
            grad_b2 = d_z2.sum(axis=0)
            d_a1 = d_z2 @ model.w2.T
            d_z1 = d_a1 * (z1 > 0.0)
            grad_w1 = x.T @ d_z1
            grad_b1 = d_z1.sum(axis=0)
            gradients = [grad_w1, grad_b1, grad_w2, grad_b2, grad_w3, grad_b3]

            step += 1
            for index, (parameter, gradient) in enumerate(zip(parameters, gradients)):
                np.clip(gradient, -10.0, 10.0, out=gradient)
                first_moment[index] = beta1 * first_moment[index] + (1.0 - beta1) * gradient
                second_moment[index] = beta2 * second_moment[index] + (1.0 - beta2) * (gradient * gradient)
                m_hat = first_moment[index] / (1.0 - beta1**step)
                v_hat = second_moment[index] / (1.0 - beta2**step)
                parameter -= learning_rate * m_hat / (np.sqrt(v_hat) + epsilon)

        train_rmse = math.sqrt(epoch_loss / seen)
        validation_rmse = evaluate_float_training(model, x_validation, y_validation)
        record = {
            "epoch": float(epoch),
            "train_rmse_normalized": train_rmse,
            "validation_rmse_normalized": validation_rmse,
        }
        history.append(record)
        print(
            f"EPOCH {epoch:02d}: train_rmse={train_rmse * 100.0:.4f}% "
            f"validation_rmse={validation_rmse * 100.0:.4f}%"
        )
        if validation_rmse < best_rmse - 1.0e-6:
            best_rmse = validation_rmse
            best_parameters = [value.copy() for value in parameters]
            epochs_without_improvement = 0
        else:
            epochs_without_improvement += 1
            if epochs_without_improvement >= patience:
                print(f"EARLY_STOP epoch={epoch}, best_validation={best_rmse * 100.0:.4f}%")
                break

    for destination, source in zip(parameters, best_parameters):
        destination[...] = source
    return model, history


def deployment_float_model(training_model: FloatModel) -> FloatModel:
    return FloatModel(
        w1=(training_model.w1 / 128.0).astype(np.float32),
        b1=training_model.b1.copy(),
        w2=training_model.w2.copy(),
        b2=training_model.b2.copy(),
        w3=(training_model.w3 * 1000.0).astype(np.float32),
        b3=(training_model.b3 * 1000.0).astype(np.float32),
    )


def float_infer(model: FloatModel, x_q: np.ndarray) -> np.ndarray:
    a1 = np.maximum(x_q.astype(np.float32) @ model.w1 + model.b1, 0.0)
    a2 = np.maximum(a1 @ model.w2 + model.b2, 0.0)
    return np.clip(a2 @ model.w3 + model.b3, 0.0, 1000.0)


def int8_weights(weights: np.ndarray, fraction_bits: int) -> np.ndarray | None:
    quantized = np.rint(weights.astype(np.float64) * (2.0**fraction_bits))
    if np.max(np.abs(quantized)) > 127 or np.all(quantized == 0):
        return None
    return quantized.astype(np.int8)


def int32_bias(bias: np.ndarray, fraction_bits: int) -> np.ndarray | None:
    quantized = np.rint(bias.astype(np.float64) * (2.0**fraction_bits))
    limit = np.iinfo(np.int32)
    if np.any(quantized < limit.min) or np.any(quantized > limit.max):
        return None
    return quantized.astype(np.int32)


def calibrate_quant_model(
    model: FloatModel,
    calibration_x: np.ndarray,
    calibration_y: np.ndarray,
) -> QuantModel:
    x64 = calibration_x.astype(np.int64)
    float_l1 = np.maximum(x64.astype(np.float32) @ model.w1 + model.b1, 0.0)
    best_l1: tuple[float, int, int, np.ndarray, np.ndarray, np.ndarray] | None = None
    for weight_fraction in range(-8, 16):
        weight = int8_weights(model.w1, weight_fraction)
        bias = int32_bias(model.b1, weight_fraction)
        if weight is None or bias is None:
            continue
        accumulator = x64 @ weight.astype(np.int64) + bias.astype(np.int64)
        for activation_fraction in range(0, min(weight_fraction, 8) + 1):
            shift = weight_fraction - activation_fraction
            activation = np.clip(accumulator >> shift, 0, 127).astype(np.int8)
            reconstructed = activation.astype(np.float32) / (1 << activation_fraction)
            scale = max(float(np.mean(float_l1**2)), 1.0e-9)
            saturation = float(np.mean(activation == 127))
            score = float(np.mean((reconstructed - float_l1) ** 2) / scale + 5.0 * saturation)
            candidate = (score, weight_fraction, activation_fraction, weight, bias, activation)
            if best_l1 is None or score < best_l1[0]:
                best_l1 = candidate
    if best_l1 is None:
        raise RuntimeError("Không tìm được lượng tử hóa hợp lệ cho layer 1")
    _, l1_w_fraction, l1_a_fraction, q_w1, q_b1, q_a1 = best_l1

    float_l2 = np.maximum(float_l1 @ model.w2 + model.b2, 0.0)
    best_l2: tuple[float, int, int, np.ndarray, np.ndarray, np.ndarray] | None = None
    for weight_fraction in range(-8, 16):
        weight = int8_weights(model.w2, weight_fraction)
        bias_fraction = l1_a_fraction + weight_fraction
        bias = int32_bias(model.b2, bias_fraction)
        if weight is None or bias is None:
            continue
        if bias_fraction < 0:
            continue
        accumulator = q_a1.astype(np.int64) @ weight.astype(np.int64) + bias.astype(np.int64)
        for activation_fraction in range(0, min(bias_fraction, 8) + 1):
            shift = bias_fraction - activation_fraction
            activation = np.clip(accumulator >> shift, 0, 127).astype(np.int8)
            reconstructed = activation.astype(np.float32) / (1 << activation_fraction)
            scale = max(float(np.mean(float_l2**2)), 1.0e-9)
            saturation = float(np.mean(activation == 127))
            score = float(np.mean((reconstructed - float_l2) ** 2) / scale + 5.0 * saturation)
            candidate = (score, weight_fraction, activation_fraction, weight, bias, activation)
            if best_l2 is None or score < best_l2[0]:
                best_l2 = candidate
    if best_l2 is None:
        raise RuntimeError("Không tìm được lượng tử hóa hợp lệ cho layer 2")
    _, l2_w_fraction, l2_a_fraction, q_w2, q_b2, q_a2 = best_l2

    best_out: tuple[float, int, np.ndarray, np.ndarray] | None = None
    for weight_fraction in range(-8, 16):
        weight = int8_weights(model.w3, weight_fraction)
        accumulator_fraction = l2_a_fraction + weight_fraction
        bias = int32_bias(model.b3, accumulator_fraction)
        if weight is None or bias is None or accumulator_fraction > 30:
            continue
        accumulator = q_a2.astype(np.int64) @ weight.astype(np.int64) + bias.astype(np.int64)
        prediction = np.clip(accumulator >> accumulator_fraction, 0, 1000)
        score = float(np.mean((prediction.astype(np.float64) - calibration_y) ** 2))
        candidate = (score, weight_fraction, weight, bias)
        if best_out is None or score < best_out[0]:
            best_out = candidate
    if best_out is None:
        raise RuntimeError("Không tìm được lượng tử hóa hợp lệ cho output")
    _, out_w_fraction, q_w3, q_b3 = best_out

    quantized = QuantModel(
        w1=q_w1,
        b1=q_b1,
        w2=q_w2,
        b2=q_b2,
        w3=q_w3,
        b3=q_b3,
        l1_shift=l1_w_fraction - l1_a_fraction,
        l2_shift=l1_a_fraction + l2_w_fraction - l2_a_fraction,
        out_shift=l2_a_fraction + out_w_fraction,
        l1_fraction_bits=l1_w_fraction,
        l1_activation_fraction_bits=l1_a_fraction,
        l2_fraction_bits=l2_w_fraction,
        l2_activation_fraction_bits=l2_a_fraction,
        out_fraction_bits=out_w_fraction,
    )
    verify_accumulator_bounds(quantized, calibration_x)
    return quantized


def bitexact_infer(model: QuantModel, x_q: np.ndarray) -> np.ndarray:
    x64 = x_q.astype(np.int64)
    acc1 = x64 @ model.w1.astype(np.int64) + model.b1.astype(np.int64)
    a1 = np.clip(acc1 >> model.l1_shift, 0, 127).astype(np.int8)
    acc2 = a1.astype(np.int64) @ model.w2.astype(np.int64) + model.b2.astype(np.int64)
    a2 = np.clip(acc2 >> model.l2_shift, 0, 127).astype(np.int8)
    acc3 = a2.astype(np.int64) @ model.w3.astype(np.int64) + model.b3.astype(np.int64)
    return np.clip(acc3 >> model.out_shift, 0, 1000).astype(np.int32)


def verify_accumulator_bounds(model: QuantModel, x_q: np.ndarray) -> None:
    x64 = x_q.astype(np.int64)
    acc1 = x64 @ model.w1.astype(np.int64) + model.b1.astype(np.int64)
    a1 = np.clip(acc1 >> model.l1_shift, 0, 127)
    acc2 = a1 @ model.w2.astype(np.int64) + model.b2.astype(np.int64)
    a2 = np.clip(acc2 >> model.l2_shift, 0, 127)
    acc3 = a2 @ model.w3.astype(np.int64) + model.b3.astype(np.int64)
    limits = np.iinfo(np.int32)
    for name, value in (("L1", acc1), ("L2", acc2), ("OUT", acc3)):
        if value.min() < limits.min or value.max() > limits.max:
            raise RuntimeError(f"Accumulator {name} vượt INT32: {value.min()}..{value.max()}")


def metric_dict(prediction_tenths: np.ndarray, target_tenths: np.ndarray) -> dict[str, float]:
    error_percent = (prediction_tenths.astype(np.float64) - target_tenths.astype(np.float64)) / 10.0
    return {
        "mae_percent": float(np.mean(np.abs(error_percent))),
        "rmse_percent": float(np.sqrt(np.mean(error_percent**2))),
        "max_abs_error_percent": float(np.max(np.abs(error_percent))),
        "bias_percent": float(np.mean(error_percent)),
    }


def evaluate_models(
    float_model: FloatModel,
    quant_model: QuantModel,
    datasets: dict[str, tuple[np.ndarray, np.ndarray]],
) -> dict[str, dict[str, dict[str, float]]]:
    metrics: dict[str, dict[str, dict[str, float]]] = {}
    for split, (x_q, y) in datasets.items():
        float_prediction = float_infer(float_model, x_q)
        quant_prediction = bitexact_infer(quant_model, x_q)
        metrics[split] = {
            "float": metric_dict(float_prediction, y),
            "quantized_bitexact": metric_dict(quant_prediction, y),
            "quantization_delta": metric_dict(quant_prediction, float_prediction),
        }
        q = metrics[split]["quantized_bitexact"]
        print(f"METRIC {split:10s}: MAE={q['mae_percent']:.4f}% RMSE={q['rmse_percent']:.4f}% MAX={q['max_abs_error_percent']:.4f}%")
    return metrics


def write_hex(path: Path, values: np.ndarray, width_bits: int) -> None:
    mask = (1 << width_bits) - 1
    digits = width_bits // 4
    lines = [f"{int(value) & mask:0{digits}X}" for value in values.reshape(-1)]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_mif(path: Path, values: np.ndarray, width_bits: int) -> None:
    mask = (1 << width_bits) - 1
    digits = width_bits // 4
    flat = values.reshape(-1)
    lines = [
        f"DEPTH = {flat.size};",
        f"WIDTH = {width_bits};",
        "ADDRESS_RADIX = DEC;",
        "DATA_RADIX = HEX;",
        "CONTENT BEGIN",
    ]
    lines.extend(f"    {index} : {int(value) & mask:0{digits}X};" for index, value in enumerate(flat))
    lines.append("END;")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def export_artifacts(
    output_dir: Path,
    float_model: FloatModel,
    quant_model: QuantModel,
    centers: np.ndarray,
    scales: np.ndarray,
    metrics: dict[str, object],
    history: list[dict[str, float]],
    infos: list[SeriesInfo],
    archives: Sequence[Path],
    verification_x: np.ndarray,
    verification_y: np.ndarray,
    seed: int,
) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(output_dir / "float_model.npz", **{name: value for name, value in zip(("w1", "b1", "w2", "b2", "w3", "b3"), model_arrays(float_model))})
    np.savez_compressed(
        output_dir / "quant_model.npz",
        w1=quant_model.w1,
        b1=quant_model.b1,
        w2=quant_model.w2,
        b2=quant_model.b2,
        w3=quant_model.w3,
        b3=quant_model.b3,
    )

    l1_flat = quant_model.w1.T.reshape(-1)
    l2_flat = quant_model.w2.T.reshape(-1)
    out_flat = quant_model.w3.reshape(-1)
    write_hex(output_dir / "l1_weights.hex", l1_flat, 8)
    write_mif(output_dir / "l1_weights.mif", l1_flat, 8)
    write_hex(output_dir / "l1_biases.hex", quant_model.b1, 32)
    write_hex(output_dir / "l2_weights.hex", l2_flat, 8)
    write_mif(output_dir / "l2_weights.mif", l2_flat, 8)
    write_hex(output_dir / "l2_biases.hex", quant_model.b2, 32)
    write_hex(output_dir / "out_weights.hex", out_flat, 8)
    write_hex(output_dir / "out_bias.hex", quant_model.b3, 32)

    verification_prediction = bitexact_infer(quant_model, verification_x)
    write_hex(output_dir / "verification_features.hex", verification_x[0], 8)
    write_hex(output_dir / "verification_expected.hex", verification_prediction[0], 32)
    verification = {
        "target_soc_tenths": float(verification_y[0, 0]),
        "expected_rtl_soc_tenths": int(verification_prediction[0, 0]),
        "feature_vector_order": "20 samples, each [voltage,current,temperature,delta_t]",
    }
    write_json(output_dir / "verification_meta.json", verification)

    model_id_source = b"".join(
        array.tobytes()
        for array in (quant_model.w1, quant_model.b1, quant_model.w2, quant_model.b2, quant_model.w3, quant_model.b3)
    )
    model_id = hashlib.sha256(model_id_source).hexdigest()[:16].upper()
    manifest = {
        "schema_version": 1,
        "model_id": model_id,
        "seed": seed,
        "topology": [INPUT_COUNT, L1_COUNT, L2_COUNT, 1],
        "sequence_length": SEQUENCE_LENGTH,
        "features": list(FEATURE_NAMES),
        "feature_center": centers.tolist(),
        "feature_scale": scales.tolist(),
        "current_sign": "positive_is_charge",
        "sample_period_ms": int(SAMPLE_PERIOD_S * 1000.0),
        "nominal_capacity_ah": RATED_CAPACITY_AH,
        "label_method": (
            "Coulomb counting on Step_Index 7/8; effective capacity is inferred "
            "from the known initial SOC and the full dynamic-profile discharge"
        ),
        "split": {
            "train": sorted(TRAIN_PROFILES),
            "validation": sorted(VALIDATION_PROFILES),
            "test": sorted(TEST_PROFILES),
        },
        "quantization": {
            "weights": "signed_int8_symmetric_power_of_two",
            "bias_accumulator": "signed_int32",
            "activation": "relu_then_unsigned_range_0_127_stored_in_int8",
            "l1_shift": quant_model.l1_shift,
            "l2_shift": quant_model.l2_shift,
            "out_shift": quant_model.out_shift,
            "l1_weight_fraction_bits": quant_model.l1_fraction_bits,
            "l1_activation_fraction_bits": quant_model.l1_activation_fraction_bits,
            "l2_weight_fraction_bits": quant_model.l2_fraction_bits,
            "l2_activation_fraction_bits": quant_model.l2_activation_fraction_bits,
            "out_weight_fraction_bits": quant_model.out_fraction_bits,
        },
        "source_archives": {path.name: sha256(path) for path in archives},
        "series": [info.__dict__ for info in infos],
        "metrics": metrics,
        "verification": verification,
    }
    write_json(output_dir / "model_manifest.json", manifest)
    write_json(output_dir / "training_history.json", history)
    return manifest


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def install_model(repo_root: Path, output_dir: Path, manifest: dict[str, object]) -> None:
    firmware_model = repo_root / "firmware" / "model"
    firmware_model.mkdir(parents=True, exist_ok=True)
    names = (
        "l1_weights.hex",
        "l1_weights.mif",
        "l1_biases.hex",
        "l2_weights.hex",
        "l2_weights.mif",
        "l2_biases.hex",
        "out_weights.hex",
        "out_bias.hex",
        "verification_features.hex",
        "verification_expected.hex",
        "verification_meta.json",
        "model_manifest.json",
    )
    for name in names:
        shutil.copy2(output_dir / name, firmware_model / name)

    centers = manifest["feature_center"]
    scales = manifest["feature_scale"]
    quantization = manifest["quantization"]
    model_id = manifest["model_id"]
    c_header = f"""#ifndef MODEL_CONFIG_H
#define MODEL_CONFIG_H

#include <stdint.h>

/* File sinh tự động bởi ml/train_quantize_export.py. Không sửa bằng tay. */
#define MODEL_ID \"{model_id}\"
#define MODEL_SEQUENCE_LENGTH {SEQUENCE_LENGTH}
#define MODEL_FEATURE_COUNT {FEATURE_COUNT}
#define MODEL_INPUT_COUNT {INPUT_COUNT}

enum model_feature_index {{
    MODEL_VOLTAGE = 0,
    MODEL_CURRENT = 1,
    MODEL_TEMPERATURE = 2,
    MODEL_DELTA_TIME = 3
}};

/* Đơn vị raw: mV, mA, 0.1 độ C, ms. Phép chia nguyên cắt về 0. */
static const int32_t model_feature_center[MODEL_FEATURE_COUNT] = {{
    {", ".join(str(value) for value in centers)}
}};

static const int32_t model_feature_scale[MODEL_FEATURE_COUNT] = {{
    {", ".join(str(value) for value in scales)}
}};

#endif
"""
    atomic_write_text(repo_root / "firmware" / "include" / "model_config.h", c_header)

    verilog_header = f"""`ifndef QNN_MODEL_CONFIG_VH
`define QNN_MODEL_CONFIG_VH

// File sinh tự động bởi ml/train_quantize_export.py. Không sửa bằng tay.
`define QNN_MODEL_ID 64'h{model_id}
`define QNN_MODEL_L1_SHIFT {quantization['l1_shift']}
`define QNN_MODEL_L2_SHIFT {quantization['l2_shift']}
`define QNN_MODEL_OUT_SHIFT {quantization['out_shift']}

`endif
"""
    atomic_write_text(repo_root / "rtl" / "accelerator" / "qnn_model_config.vh", verilog_header)
    print(f"INSTALLED model_id={model_id} -> firmware/model và generated headers")


def main() -> int:
    args = parse_args()
    if args.epochs < 1 or args.batch_size < 1:
        raise ValueError("epochs và batch-size phải dương")
    repo_root = args.repo_root.resolve()
    raw_dir = repo_root / "ml" / "data" / "raw"
    sums_path = repo_root / "ml" / "data" / "SHA256SUMS.txt"
    output_dir = repo_root / "ml" / "artifacts" / "model"

    random.seed(args.seed)
    np.random.seed(args.seed)
    rng = np.random.default_rng(args.seed)
    start_time = time.perf_counter()

    archives = verify_archives(raw_dir, sums_path)
    raw_datasets, infos = load_dataset(archives, args.train_stride, args.eval_stride)
    centers, scales = derive_feature_quantization(raw_datasets["train"][0])
    print(f"FEATURE center={centers.tolist()} scale={scales.tolist()}")

    quantized_datasets: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    for split, (raw_x, y_tenths) in raw_datasets.items():
        quantized_datasets[split] = (quantize_features(raw_x, centers, scales), y_tenths)
        saturation = np.mean(
            (quantized_datasets[split][0] == -128) | (quantized_datasets[split][0] == 127)
        )
        print(f"FEATURE {split:10s}: windows={raw_x.shape[0]}, saturation={100.0 * saturation:.4f}%")

    train_x_q, train_y_tenths = quantized_datasets["train"]
    validation_x_q, validation_y_tenths = quantized_datasets["validation"]
    training_model, history = train_model(
        train_x_q.astype(np.float32) / 128.0,
        train_y_tenths.astype(np.float32) / 1000.0,
        validation_x_q.astype(np.float32) / 128.0,
        validation_y_tenths.astype(np.float32) / 1000.0,
        args.epochs,
        args.batch_size,
        args.learning_rate,
        rng,
    )
    float_model = deployment_float_model(training_model)

    calibration_count = min(4096, train_x_q.shape[0])
    calibration_indices = rng.choice(train_x_q.shape[0], calibration_count, replace=False)
    quant_model = calibrate_quant_model(
        float_model,
        train_x_q[calibration_indices],
        train_y_tenths[calibration_indices],
    )
    print(
        f"QUANT shifts: L1={quant_model.l1_shift}, "
        f"L2={quant_model.l2_shift}, OUT={quant_model.out_shift}"
    )
    metrics = evaluate_models(float_model, quant_model, quantized_datasets)

    test_x, test_y = quantized_datasets["test"]
    middle = int(np.argmin(np.abs(test_y[:, 0] - np.median(test_y[:, 0]))))
    manifest = export_artifacts(
        output_dir,
        float_model,
        quant_model,
        centers,
        scales,
        metrics,
        history,
        infos,
        archives,
        test_x[[middle]],
        test_y[[middle]],
        args.seed,
    )

    test_rmse = metrics["test"]["quantized_bitexact"]["rmse_percent"]
    if args.install:
        if test_rmse > args.max_install_rmse:
            raise RuntimeError(
                f"Không cài model: test RMSE {test_rmse:.4f}% vượt ngưỡng "
                f"{args.max_install_rmse:.4f}%"
            )
        install_model(repo_root, output_dir, manifest)

    elapsed = time.perf_counter() - start_time
    print(f"DONE output={output_dir} elapsed={elapsed:.1f}s")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # In lỗi ngắn gọn; traceback vẫn hữu ích khi phát triển.
        print(f"ERROR: {error}", file=sys.stderr)
        raise
