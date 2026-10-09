# Làm rõ mã core RV32I — 2026-09-29

Báo cáo này ghi lại đợt chỉ sửa chú thích/khoảng trắng. Core sau đợt này được
lưu trong `core_module_baseline_20260929.zip`; việc tách module tiếp theo được
ghi riêng tại [báo cáo tách module](bao_cao_tach_module_core_vi.md).

## Phạm vi và căn cứ

Theo yêu cầu hiện tại của người dùng, đợt này tập trung làm mã core sạch,
dễ đọc và dễ hiểu, giữ nguyên logic; chú thích và tài liệu viết bằng tiếng Việt.
Báo cáo `RV32I_SoC_Readability_Refactor_Report.md` được dùng làm tài liệu tham
khảo. Checklist về bus, ngoại vi và firmware trong báo cáo không được tự động
mở rộng thành phạm vi thực hiện.

Yêu cầu mới cho phép chỉnh cách trình bày của core đang đóng băng. Không phát
hiện/sửa lỗi chức năng, không thử tối ưu timing, không mở rộng kiến trúc. Toàn
bộ token Verilog, thứ tự khai báo, biểu thức, kết nối cổng và các phép gán giữ
nguyên. Các thay đổi RTL chỉ gồm chú thích và khoảng trắng.

## Cách tổ chức mã

| Tệp trong `rtl/core/` | Thay đổi để dễ đọc |
|---|---|
| `rv32_core.v` | Tách rõ trạng thái pipeline, đường dữ liệu, điều khiển, kết nối IF → WB và cập nhật tại cạnh lên; gom mô tả tín hiệu lặp; căn cổng theo instance |
| `if/rv32_if_stage.v` | Nhóm giữ yêu cầu, chờ đáp ứng, FIFO và giới hạn hai chỗ; giải thích flush/kill, nhận và trả dữ liệu đồng thời |
| `control/rv32_pipeline_control.v` | Nhóm nguồn tín hiệu theo tầng; giải thích phân xử MEM/EX/ID và thời điểm lấy đầu FIFO |
| `control/rv32_hazard_unit.v` | Làm rõ phụ thuộc load-use, nguồn chuyển tiếp và ưu tiên EX/MEM trước MEM/WB |
| `id/rv32_id_stage.v` | Nhóm giải mã, immediate, thanh ghi và ngoại lệ; làm rõ đường tắt WB → ID |
| `ex/rv32_ex_stage.v` | Nhóm toán hạng, chuyển tiếp, ALU/nhánh và kiểm tra căn hàng |
| `mem/rv32_mem_stage.v` | Nhóm giao dịch dữ liệu, LSU, tín hiệu chờ/lỗi và nguồn ghi về |
| `wb/rv32_wb_stage.v` | Làm rõ điều kiện ghi thanh ghi, phát vết hoàn tất và chốt trap |

Bảy tệp core còn lại giữ nguyên từng byte. Không đổi testbench hiện có.
Không đổi RTL ngoài core, QSF/SDC hay ảnh ROM `firmware/build/boot.*`.

Các quy tắc nhạy cảm được giữ nguyên và chú thích tại nơi sử dụng:

- Khi MEM chờ, EX/MEM giữ lại, WB cũ hoàn tất một lần rồi xóa valid.
  Hai toán hạng ID/EX vẫn nhận giá trị sau chuyển tiếp để không mất dữ liệu WB.
- EX/MEM không chuyển tiếp địa chỉ của load như dữ liệu đọc.
- Yêu cầu fetch đã phát vẫn giữ đến grant dù gặp redirect; đáp ứng sai đường
  được nhận và loại bỏ. Các cờ kill không mất qua nhiều lần flush.
- Lỗi MEM có ưu tiên hơn lệnh trẻ ở EX/ID; lệnh lỗi đi tới WB, không ghi rd
  và không phát vết hoàn tất thành công.

[Hướng dẫn đọc core](doc_hieu_core_vi.md) bổ sung bảng dữ liệu giữa các tầng,
ưu tiên sự kiện, ví dụ ADDI/LW/SW, chuyển tiếp toán hạng, dạng sóng hai giao
thức bộ nhớ và bảng tìm tệp khi debug.

## Đối chiếu bản đóng băng

Trước khi sửa, `scripts/check_core_freeze.py` báo **PASS 15/15**, khớp manifest
ngày 2026-09-27. Bản gốc của cả 15 tệp và manifest gốc được lưu tại
[`core_readability_baseline_20260929.zip`](core_readability_baseline_20260929.zip).

SHA256 của bản lưu:

```text
3546d48583c452ca1c147f108d8f7c258b7ab53edfdf5eafdfaeb0fa4cf89dbd
```

[`check_core_readability.py`](../scripts/check_core_readability.py) kiểm tra
hash bản lưu, từng tệp gốc theo manifest gốc, danh sách tệp hiện tại và token
Verilog. Bộ đối chiếu giữ chuỗi, ranh giới toán tử, dòng chỉ thị tiền xử lý
và chú thích có tác động tới công cụ. Nó từ chối macro phụ thuộc vị trí mã.
Đây là kiểm tra thay đổi cách trình bày của bộ mã này, không phải chứng minh
tương đương cho một phép biến đổi logic tùy ý.

Sau chỉnh sửa, **15/15 tệp giữ nguyên token**, trong đó 8 tệp đổi byte do
cách trình bày. Vì vậy, kiểm tra hash cũ phát hiện đúng 8 mismatch trước khi
chốt lại. Không sửa `check_core_freeze.py` để bỏ qua các mismatch.

Sau khi rà soát nội dung và hoàn tất các kiểm tra dưới đây, manifest được
chốt lại cho bản trình bày ngày 2026-09-29. Manifest ghi rõ lý do, bằng chứng
mới và đường dẫn bản lưu gốc; thông tin ngày 2026-09-27 vẫn được giữ riêng.
`check_core_freeze.py` tiếp tục kiểm tra chính xác từng byte của bản hiện tại,
còn `check_core_readability.py` đối chiếu token với bản gốc đã xác minh ISA.

## Xác minh trong đợt này

| Hạng mục | Kết quả | Bằng chứng |
|---|---|---|
| Token so với core gốc | PASS 15/15 | `scripts/check_core_readability.py` |
| Icarus toàn bộ | PASS 32/32 | `sim/iverilog/work/*.log` |
| ISA upstream và local | PASS 195/195 | `sim/isa/results.json` |
| ModelSim toàn bộ và stress | PASS 78/78 | `tmp/readability_modelsim_regression.log` |
| Quartus compile | 0 lỗi, 14 cảnh báo như baseline | `tmp/readability_quartus.log` |
| Setup/hold/recovery/removal | PASS cả ba corner | `quartus/output_files/riscv_soc.sta.summary` |
| Hash bản chốt cuối | PASS 15/15 | `scripts/check_core_freeze.py` |

Fmax vẫn **54,86 MHz**. Slack nhỏ nhất lần lượt là setup **+1,772 ns**,
hold **+0,097 ns**, recovery **+17,049 ns**, removal **+1,069 ns**, giống số
liệu baseline. Tài nguyên vẫn 6.353 logic element, 3.184 thanh ghi,
338.944 bit bộ nhớ và 3 phần tử nhân 9 bit. Không có cảnh báo mới; vị trí dòng
`KEY[1]` trong cảnh báo khác bản ngày 2026-09-27 do đợt chuẩn hóa board đã có
trước công việc này. Không coi việc chỉnh trình bày là một tối ưu timing.

Các bộ test có giao nhau, không cộng số lượt thành số kiểm thử độc lập.
Lượt ModelSim/Quartus đầu bị dừng theo yêu cầu tạm dừng của người dùng;
lượt xác minh cuối được chạy lại khi người dùng yêu cầu tiếp tục.

## Tái lập

Từ thư mục gốc dự án trên Windows:

```powershell
.\.tools\python311\python.exe scripts/check_core_readability.py --source-archive docs/core_module_baseline_20260929.zip
.\.tools\python311\python.exe scripts/check_core_freeze.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_tests.ps1 -Scope All -Stress
wsl -d Ubuntu -- python3 scripts/run_tests.py --scope all
wsl -d Ubuntu -- python3 scripts/run_isa.py
```

Từ `quartus/`, chạy `quartus_sh --flow compile riscv_soc` bằng Quartus 20.1.
Các thay đổi hiện tại không thêm test RTL hoặc thay dữ liệu kiểm thử để đạt
PASS. Chưa thực hiện kiểm chứng trên board trong đợt này.
