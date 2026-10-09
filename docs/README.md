# Tài liệu RV32I QNN SoC trên DE10-Lite

Dự án kết hợp core RV32I pipeline 5 tầng, bus/ngoại vi, firmware INA228 và
accelerator QNN cho bài toán ước lượng trạng thái sạc pin. Bắt đầu từ ba tài
liệu sau để hiểu thiết kế và phạm vi đã kiểm chứng:

1. [Kiến trúc RV32I](kien_truc_rv32i_vi.md): pipeline, forwarding, stall/flush và precise trap.
2. [SoC và QNN](soc_qnn_de10_lite_vi.md): luồng dữ liệu, MMIO, accelerator và firmware.
3. [Kiểm chứng ISA](isa_verification_vi.md): 195 lượt kiểm thử, coverage, giới hạn và cách chạy lại.

## Thiết kế và tích hợp

| Tài liệu | Nội dung |
|---|---|
| [Hướng dẫn đọc RTL](doc_hieu_core_vi.md) | Lần theo module, tín hiệu và dạng sóng của core hiện tại |
| [Đặc tả core, bus và ngoại vi](dac_ta_core_bus_ngoai_vi.md) | Memory map, thanh ghi MMIO, latency và lỗi truy cập |
| [Giao tiếp RTL](giao_tiep_rtl_vi.md) | Bảng cổng, handshake, reset và trace |
| [Phạm vi ISA](isa_scope_vi.md) | Instruction hỗ trợ, alignment và chính sách ngoại lệ |
| [Firmware INA228](firmware_ina228_vi.md) | Driver cảm biến, vòng đệm 20 mẫu và cấu hình cần xác nhận |

## Kiểm chứng và triển khai

| Tài liệu | Nội dung |
|---|---|
| [Module và testbench](module_va_testbench_vi.md) | Contract từng module và cách xây dựng kiểm thử |
| [Báo cáo freeze](bao_cao_freeze_isa_soc_vi.md) | Mốc kiểm chứng ngày 27/09/2026: ISA, regression, firmware, tài nguyên và timing |
| [Review timing](timing_review_freeze_vi.md) | Critical path, phương án tối ưu và slack ở ba corner |
| [Kiểm chứng board](kiem_chung_board_vi.md) | Trình tự chạy phần cứng và biên bản kết quả cần ghi |
| [Kết nối INA228 → ESP32-C3 → DE10-Lite](kich_ban_ket_noi_esp32c3_ina228_de10_lite_vi.md) | Đi dây và kiểm tra luồng nhận dữ liệu UART theo từng đoạn |
| [Manifest core](core_frozen_manifest.json) | SHA256 cho kiểm tra baseline bằng `scripts/check_core_freeze.py` |

Các kết quả mô phỏng và timing có ngày, phạm vi và giới hạn riêng; báo cáo
freeze ghi nhận mốc lịch sử, còn manifest kiểm tra mã core hiện tại. Dự án
chưa xác nhận chạy end-to-end trên board thật. Hướng dẫn board là quy trình
kiểm chứng cần thực hiện, không phải bằng chứng phép đo đã hoàn tất.

Lệnh build và regression nằm trong [README dự án](../README.md). Báo cáo sửa
code theo từng đợt, inventory lịch sử và ZIP sao lưu được giữ cục bộ, bỏ qua
bởi `.gitignore`.
