# Tách module core RV32I — 2026-09-30

## Mục đích và phạm vi

Theo yêu cầu trực tiếp của người dùng sau đợt làm rõ chú thích, core được tách
thành các module nhỏ theo trách nhiệm. Đây là thay đổi cấu trúc mã, vượt quá
chỉnh khoảng trắng; không áp dụng kết luận “token không đổi” của đợt trước
cho bản hiện tại. Giữ nguyên giao tiếp core, ISA, năm tầng pipeline, biểu thức
xử lý, thứ tự ưu tiên và thời điểm các tác dụng phụ. Chú thích và đặc tả dùng
tiếng Việt.

Yêu cầu tách module là căn cứ cho ngoại lệ cấu trúc đối với chính sách đóng
băng. Không mở rộng hay thiết kế lại forwarding, hazard, LSU, ngoại lệ hoặc
fetch; không thực hiện tối ưu timing. Bản core trước tách đã được kiểm tra
hash thành công và lưu trước khi sửa.

## Năm module được tách

| Module mới | Trách nhiệm và điều kiện cần giữ |
|---|---|
| [rv32_id_ex_reg](../rtl/core/pipeline/rv32_id_ex_reg.v) | Chốt lệnh từ ID; hủy khi có sự kiện già hơn; chèn rỗng khi load-use. Khi MEM chờ, vẫn lưu hai toán hạng sau chuyển tiếp để không mất dữ liệu WB |
| [rv32_ex_mem_reg](../rtl/core/pipeline/rv32_ex_mem_reg.v) | Chốt kết quả EX; giữ toàn bộ khi MEM chờ; lỗi MEM xóa lệnh trẻ. Dùng lỗi EX chưa phân xử để chặn ghi rd/load/store lúc nhận EX |
| [rv32_mem_wb_reg](../rtl/core/pipeline/rv32_mem_wb_reg.v) | Chốt kết quả hoặc ngoại lệ MEM. MEM chờ thì xóa valid để WB cũ chỉ hoàn tất một lần; ngoại lệ đã có được ưu tiên khi chọn cause |
| [rv32_if_request_queue](../rtl/core/if/rv32_if_request_queue.v) | Giữ PC/cờ hủy của hai yêu cầu đã grant, chờ đáp ứng. Hủy được gán sau cập nhật hàng đợi để thắng nhận/lấy trong cùng chu kỳ |
| [rv32_if_fifo](../rtl/core/if/rv32_if_fifo.v) | Giữ hai phần tử lệnh/ngoại lệ chờ ID. Flush chỉ xóa số phần tử; thêm/lấy đồng thời giữ nguyên số lượng và thứ tự |

`rv32_core.v` không còn khối tuần tự; các instance xếp theo luồng
`IF → ID → ID/EX → EX → EX/MEM → MEM → MEM/WB → WB`, sau đó là điều khiển.
Tên dây `idex_*_q`, `exmem_*_q`, `memwb_*_q` ở top được giữ để theo dõi dữ liệu.
Chúng là dây nối trạng thái trong module con.

`rv32_if_stage` giữ PC, trạng thái dừng phát, yêu cầu đang chờ grant và các
biểu thức tính chỗ trống/bắt tay. Hai hàng đợi cùng chia sẻ giới hạn tổng hai
chỗ; việc tách module không tăng số yêu cầu được phép phát.

Các module mới lần lượt dài 151, 107, 87, 94 và 117 dòng. Tầng IF giảm từ
352 xuống 269 dòng; top core từ 611 xuống 565 dòng và không còn `always`.
Tổng số dòng tăng do khai báo cổng/kết nối, nhưng mỗi khối tuần tự nay có
trách nhiệm và điều kiện giữ/hủy riêng, đọc được tại một tệp nhỏ.

`quartus/riscv_soc.qsf` thêm đúng năm tệp nguồn. Hai trình chạy regression
ModelSim/Icarus đọc danh sách từ QSF; trình chạy ISA tìm nguồn dưới `rtl/core`.
Không đổi các testbench hiện có hoặc ảnh board `firmware/build/boot.*`.

## Cách kiểm chứng

Bản tham chiếu cố định là
[`core_module_baseline_20260929.zip`](core_module_baseline_20260929.zip), gồm
15 tệp core, manifest và QSF trước tách. SHA256:

```text
30f7d0a4b68999a298f14f172bdcff8d99b6fc18059ee0695fbdbdbae811d3c9
```

[`check_core_module_equivalence.py`](../scripts/check_core_module_equivalence.py)
đổi tên module và macro của bản tham chiếu trong thư mục mô phỏng, cấp cùng
đầu vào cho hai bản và so sánh mọi cổng ra bằng `!==` sau cả hai cạnh clock
kể từ reset. Payload khi invalid cũng được so sánh. Nguồn RTL/testbench được
chụp riêng và ghi hash vào `results.json`, tránh nhầm bằng chứng giữa các bản.

Sáu testbench gốc dùng cho đối chiếu gồm core, fetch, ordering, traps, bus wait
và IF; thêm 16 seed của core. Trước tách đã đạt 22/22 ca, 36.545 lần so sánh.
Một kiểm tra âm đổi giá trị reset `retire_pc` chỉ trong bản sao mô phỏng:
bộ đối chiếu phát hiện sai khác ngay cả khi `retire_valid=0`. RTL thật và các
testbench gốc không bị sửa bởi kiểm tra này.

Đây là đối chiếu theo chu kỳ trên các kịch bản đã chạy, không phải chứng minh
tương đương hình thức cho mọi đầu vào. Regression và phân tích timing được
chạy riêng trên bản đã tách.

## Kết quả xác minh

| Kiểm tra | Kết quả | Bằng chứng |
|---|---|---|
| Đối chiếu trước tách | PASS 22/22, 36.545 lần | `sim/module_equivalence/truoc_tach/results.json` |
| Kiểm tra âm của bộ đối chiếu | PASS, bắt được sai khác cố ý | `sim/module_equivalence/kiem_tra_am_20260930/results.json` |
| Đối chiếu sau tách | PASS 22/22, 36.545 lần | `sim/module_equivalence/sau_tach/results.json` |
| ModelSim toàn bộ + stress | PASS 78/78 | `tmp/module_refactor_modelsim.log` |
| Icarus toàn bộ | PASS 32/32 | `tmp/module_refactor_icarus.log` |
| ISA | PASS 195/195 | `sim/isa/results.json` |
| Quartus | 0 lỗi, 14 cảnh báo như trước | `tmp/module_refactor_quartus.log` |
| Setup/hold/recovery/removal | PASS cả ba corner | `quartus/output_files/riscv_soc.sta.summary` |
| Manifest cuối | PASS 20/20 tệp core | `docs/core_frozen_manifest.json` |

Các bộ kiểm thử có giao nhau, không cộng các số lượt thành số ca độc lập.
Kết quả timing trước tách được lưu tại `tmp/module_refactor_before.sta.*`
và `tmp/module_refactor_before.fit.summary`. Chưa kiểm chứng board trong đợt này.

| Chỉ tiêu Quartus | Trước tách | Sau tách |
|---|---:|---:|
| Fmax, slow 85°C | 54,86 MHz | 54,61 MHz |
| Slack setup nhỏ nhất | +1,772 ns | +1,687 ns |
| Slack hold nhỏ nhất | +0,097 ns | +0,112 ns |
| Slack recovery nhỏ nhất | +17,049 ns | +17,162 ns |
| Slack removal nhỏ nhất | +1,069 ns | +1,030 ns |
| Logic element | 6.353 | 6.338 |
| Hàm tổ hợp | 5.989 | 5.989 |
| Thanh ghi | 3.184 | 3.184 |
| Bit bộ nhớ | 338.944 | 338.944 |
| Phần tử nhân 9 bit | 3 | 3 |

Fmax giảm 0,25 MHz; vẫn đạt clock 50 MHz và tất cả kiểm tra thời gian. Kết quả
đóng gói/đặt tuyến thay đổi sau khi đổi phân cấp module; số hàm tổ hợp, thanh
ghi, bộ nhớ và phần tử nhân giữ nguyên. Giữ phép tách vì mục tiêu tổ chức mã
đã được yêu cầu và hành vi theo chu kỳ khớp trên các ca kiểm thử; không coi đây
là một cải thiện timing.

## Chốt lại baseline

Kiểm tra hash trước khi chốt phát hiện đúng hai tệp core thay đổi
(`rv32_core.v`, `rv32_if_stage.v`) và năm tệp mới. Mười ba tệp core còn lại
giữ nguyên từng byte. Manifest mới chỉ được ghi sau rà soát, đối chiếu,
regression và Quartus đạt; lưu lý do tách cùng tham chiếu tới bản ZIP gốc.
Không sửa `check_core_freeze.py` để bỏ qua mismatch.

Đã đối chiếu 131 tệp ngoài phạm vi sửa, gồm RTL ngoài core, testbench hiện
có, firmware build và ràng buộc: hash không đổi. QSF chỉ bổ sung năm nguồn
RTL. `check_core_readability.py --source-archive docs/core_module_baseline_20260929.zip`
tiếp tục kiểm toán đợt sửa chú thích trước đó; không gán kết quả token của
bản lưu này cho cấu trúc core mới.

## Tái lập

Từ thư mục gốc dự án:

```powershell
wsl -d Ubuntu -- python3 scripts/check_core_module_equivalence.py --label kiem_tra_lai
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress
wsl -d Ubuntu -- python3 scripts/run_tests.py --scope all
wsl -d Ubuntu -- python3 scripts/run_isa.py
.\.tools\python311\python.exe scripts/check_core_freeze.py
```

Đổi nhãn đối chiếu ở mỗi lần chạy để giữ log cũ. Từ `quartus/`, chạy
`quartus_sh --flow compile riscv_soc` bằng Quartus 20.1.
Hướng dẫn lần theo mã và tín hiệu nằm ở [đọc hiểu core](doc_hieu_core_vi.md).
