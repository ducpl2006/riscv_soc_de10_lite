# Đọc hiểu core RV32I

Tài liệu này là bản đồ đọc RTL hiện tại, tập trung vào luồng dữ liệu và điều
khiển của core. Hợp đồng cổng, reset và tích hợp nằm trong
[đặc tả giao tiếp RTL](giao_tiep_rtl_vi.md). Các ví dụ dưới đây minh họa hành vi;
không thay thế kết quả kiểm thử hay bổ sung tính năng vào baseline đã đóng băng.

## 1. Bắt đầu từ đâu

Đọc [rv32_core.v](../rtl/core/rv32_core.v) theo ba phần: khai báo ranh giới
pipeline, nối các module con, rồi khối cập nhật thanh ghi tại cạnh lên.
Sau đó lần theo module thực hiện phép tính cần tìm:

| Tệp | Trách nhiệm |
|---|---|
| [rv32_defs.vh](../rtl/core/rv32_defs.vh) | Mã điều khiển ALU, immediate, forwarding, ghi về và nguyên nhân ngoại lệ |
| [rv32_if_stage.v](../rtl/core/if/rv32_if_stage.v) | Phát yêu cầu lấy lệnh, giữ metadata, FIFO hai phần tử, loại đáp ứng sai đường |
| [rv32_id_stage.v](../rtl/core/id/rv32_id_stage.v) | Ghép giải mã, immediate, đọc thanh ghi và ngoại lệ ID |
| [rv32_decoder.v](../rtl/core/id/rv32_decoder.v), [rv32_imm_gen.v](../rtl/core/id/rv32_imm_gen.v), [rv32_regfile.v](../rtl/core/id/rv32_regfile.v) | Chọn phép toán, dựng hằng tức thời, lưu thanh ghi và chuyển tiếp WB → ID |
| [rv32_ex_stage.v](../rtl/core/ex/rv32_ex_stage.v) | Chọn dữ liệu chuyển tiếp, toán hạng ALU, đích nhảy và lỗi căn chỉnh |
| [rv32_alu.v](../rtl/core/ex/rv32_alu.v), [rv32_branch_unit.v](../rtl/core/ex/rv32_branch_unit.v) | Tính kết quả số học/logic và điều kiện nhánh |
| [rv32_lsu.v](../rtl/core/common/rv32_lsu.v) | Kiểm tra căn chỉnh, chọn byte, tạo dữ liệu ghi và mở rộng dữ liệu đọc |
| [rv32_mem_stage.v](../rtl/core/mem/rv32_mem_stage.v) | Tạo giao dịch dữ liệu, báo chờ/lỗi, chọn dữ liệu ghi về |
| [rv32_wb_stage.v](../rtl/core/wb/rv32_wb_stage.v) | Cho phép ghi thanh ghi, xuất trace, chốt trap và trạng thái dừng |
| [rv32_hazard_unit.v](../rtl/core/control/rv32_hazard_unit.v) | Phát hiện phụ thuộc load-use, chọn nguồn chuyển tiếp cho từng toán hạng |
| [rv32_pipeline_control.v](../rtl/core/control/rv32_pipeline_control.v) | Phân xử sự kiện và quyết định ID có được lấy lệnh từ FIFO hay không |

Luồng chính là `IF/FIFO → ID → ID/EX → EX → EX/MEM → MEM → MEM/WB → WB`.
ID, EX, MEM xử lý tổ hợp; trạng thái thanh ghi chung nằm trong `rv32_core`.
IF tự giữ trạng thái lấy lệnh; register file và WB cũng có trạng thái riêng.
LSU được dùng ở EX để kiểm tra căn chỉnh, ở MEM để xử lý dữ liệu bus.

## 2. Đọc tên và dữ liệu đi kèm

- `_i`, `_o`: hướng cổng theo module khai báo, không phải vị trí trong toàn core.
- `_q`: trạng thái đã chốt. Riêng `ifid_*_q` và `halted_q` trong top là dây
  nối trạng thái do module con giữ.
- `idex_*`, `exmem_*`, `memwb_*`: dữ liệu của lệnh tại ranh giới tương ứng.
- `*_raw`: kết quả phát hiện trước phân xử toàn pipeline; `*_event`: sự kiện
  đưa vào điều khiển. Vẫn phải đọc điều kiện reset, halt và ưu tiên tại nơi dùng.
- `valid=0`: không có lệnh; những bit dữ liệu còn lại có thể giữ giá trị cũ.
  `valid=1, exc_valid=1`: có một lệnh/phần tử lỗi đang đi tới WB.

Trong bảng sau, tên trường lược bỏ tiền tố ranh giới và hậu tố `_q`.

| Ranh giới | Dữ liệu được giữ | Nơi giữ |
|---|---|---|
| IF/ID | `valid`, `pc`, `instr`, `exc_valid`, `exc_cause` | Phần tử đầu FIFO trong IF; `valid` suy ra từ số phần tử |
| ID/EX | Nhận dạng: `valid`, `pc`, `instr`, `pc4`; nguồn/đích: `rs1_addr`, `rs2_addr`, `rd_addr`, `rs1_data`, `rs2_data`; giải mã: `imm`, `funct3`, `alu_op`, `op_a_sel`, `op_b_imm`, `reg_write`, `wb_sel`, `branch`, `jal`, `jalr`, `load`, `store`; lỗi: `exc_valid`, `exc_cause` | Top core |
| EX/MEM | `valid`, `pc`, `instr`, `pc4`, `rd_addr`, `reg_write`, `wb_sel`, `alu_result`, `store_data`, `funct3`, `load`, `store`, `exc_valid`, `exc_cause` | Top core |
| MEM/WB | `valid`, `pc`, `instr`, `rd_addr`, `reg_write`, `wb_data`, `exc_valid`, `exc_cause` | Top core |

`alu_result` là kết quả tính toán; với load/store, nó là địa chỉ byte hiệu
dụng. `store_data` đã qua chuyển tiếp ở EX. `wb_data` đã chọn xong nguồn
ALU, dữ liệu đọc hoặc PC+4; WB không chọn lại nguồn này.

## 3. Giữ, chèn rỗng, xóa, đổi hướng và trap

| Thuật ngữ | Ý nghĩa trong core này |
|---|---|
| Giữ (`hold`, `stall`) | Lệnh chưa được tiến. MEM chờ làm EX/MEM và lệnh ID/EX ở lại, ID không lấy đầu FIFO. Hai toán hạng ID/EX vẫn được cập nhật bằng giá trị sau chuyển tiếp. |
| Chèn rỗng (`bubble`) | Đặt `valid=0` để không thực hiện lệnh ở vị trí đó. Load-use giữ lệnh tại ID, đưa load sang MEM và chèn rỗng vào ID/EX. |
| Xóa (`flush`) | Loại lệnh trẻ hơn do lỗi hoặc đổi hướng. Thường chỉ cần xóa `valid`/số phần tử; không cần xóa mọi bit dữ liệu. |
| Đổi hướng (`redirect`) | Branch được lấy, JAL hoặc JALR hợp lệ tại EX nạp PC đích và loại lệnh trẻ hơn. Lệnh nhảy vẫn đi tiếp để hoàn tất. |
| Trap | Ngoại lệ tới WB làm chốt `trap_*` và `halted_o` tới reset. Lệnh lỗi không ghi `rd`, không xuất `retire_valid_o`; core không nhảy tới trình xử lý trap. |

Ưu tiên phải đọc tại cả bộ điều khiển lẫn khối tuần tự top. Bảng mô tả
cạnh xử lý khi không có reset/halt ưu tiên hơn; lệnh ở WB già hơn MEM,
MEM già hơn EX, EX già hơn ID.

| Các điều kiện cùng xuất hiện | Kết quả tại cạnh xử lý |
|---|---|
| Reset và mọi sự kiện khác | Reset trạng thái, xóa pipeline; chặn yêu cầu bộ nhớ |
| `wb_trap_event` và sự kiện trẻ hơn | WB chốt trap; top xóa ba `valid`; IF xóa FIFO và đánh dấu hủy yêu cầu cũ; MEM chặn yêu cầu dữ liệu |
| Đã `halted_q=1` | Không tiến pipeline, không ghi thanh ghi; yêu cầu instruction đã phát vẫn phải được nhận và đáp ứng vẫn được thu dọn |
| `mem_stall` và lỗi/redirect EX hoặc ngoại lệ ID | EX/ID chờ; không tiêu thụ IF/ID. WB cũ hoàn tất một lần, rồi `memwb_valid_q` bị xóa |
| `mem_fault_event` và lỗi/redirect EX hoặc ngoại lệ ID | Lỗi MEM đi vào MEM/WB; xóa lệnh tại EX/ID và FIFO. Lệnh WB cũ không lỗi vẫn hoàn tất |
| Đích nhảy EX lệch hàng | `ex_fault_event` có hiệu lực; điều kiện căn chỉnh chặn redirect. Lệnh lỗi đi vào EX/MEM, các lệnh trẻ hơn bị xóa |
| Redirect EX hợp lệ và ngoại lệ/load-use tại ID | Redirect thắng; lệnh EX tiếp tục, ID/EX và FIFO bị xóa |
| Ngoại lệ giải mã ID, không có cản trở già hơn | ID chuyển lệnh lỗi vào ID/EX; IF dừng phát mới và xóa FIFO. Lỗi fetch có sẵn được giữ nguyên cause |
| Load-use, không có cản trở già hơn | ID không tiêu thụ FIFO, ID/EX thành bubble; load vẫn sang EX/MEM |

`mem_stall` và `mem_fault_event` loại trừ nhau: một bên cần `!ready`, bên
kia cần `ready && err`. Hai tín hiệu ngoại lệ ID và load-use không có quan
hệ ưu tiên trực tiếp trong các phép gán điều khiển; chúng đều bị sự kiện
MEM/EX chặn. Khối ID/EX xét load-use trước nạp dữ liệu ID, còn IF xét ngoại
lệ ID như một yêu cầu dừng/xóa. Không suy diễn một bộ mã hóa ưu tiên duy
nhất cho tất cả tín hiệu chỉ từ thứ tự các dòng trong bảng.

## 4. Theo dấu ba lệnh

Các đường đi dưới đây giả sử lệnh hợp lệ, địa chỉ hợp lệ và không bị lệnh
già hơn xóa. Chu kỳ chờ có thể kéo dài thời gian ở một tầng.

| Lệnh ví dụ | ID | EX | MEM | WB |
|---|---|---|---|---|
| `addi x5,x1,12` | Đọc x1, mở rộng dấu immediate 12, chọn ALU cộng, `WB_ALU` | Chọn x1 sau chuyển tiếp, cộng 12 | Chuyển kết quả ALU, không phát data request | Ghi x5 và xuất trace |
| `lw x6,0(x5)` | Đọc x5, đặt `load=1`, `WB_LOAD`, cỡ word | Cộng địa chỉ, kiểm tra chia hết cho 4 | Giữ yêu cầu đọc tới `req && ready`; chọn word đọc nếu thành công | Ghi x6 và xuất trace |
| `sw x6,4(x5)` | Đọc x5 và x6, immediate dạng S; `store=1`, không ghi rd | Cộng địa chỉ; chuyển tiếp x6 vào `store_data`; kiểm tra căn chỉnh | `we=1`, word căn hàng, `wstrb=1111`; chờ hoàn tất | Xuất trace với `retire_rd_we=0` |

Với chuỗi liền nhau ở trên, ADDI có thể chuyển kết quả từ EX/MEM tới EX
cho địa chỉ LW. Nếu SW ở ID khi LW ở EX, phụ thuộc dữ liệu x6 cần bubble
load-use; sau khi load hoàn tất MEM, SW tới EX và nhận dữ liệu từ MEM/WB.
Khoảng trống do chờ lấy lệnh có thể làm phụ thuộc được giải quyết muộn hơn
mà không cần bubble riêng. Nếu địa chỉ lệch hàng, EX gắn cause 4/6 và chặn
load/store trước MEM; nếu bus báo lỗi, MEM gắn cause 5/7.
LW tới x0 vẫn thực hiện truy cập và vẫn có thể trap; chỉ việc ghi x0 bị bỏ qua.

## 5. Chuyển tiếp và chờ MEM

| Cặp nguồn → nơi dùng | Điều kiện và giá trị |
|---|---|
| EX/MEM → EX.rs1/rs2 | Lệnh nguồn hợp lệ, không lỗi, ghi `rd!=0`, không phải load; trùng chỉ số nguồn. Dùng ALU hoặc PC+4, mã chọn `10` |
| MEM/WB → EX.rs1/rs2 | Lệnh nguồn hợp lệ, không lỗi, ghi `rd!=0`, trùng chỉ số nguồn; dùng `wb_data`, mã `01` |
| ID/EX → EX.rs1/rs2 | Không có nguồn chuyển tiếp phù hợp; dùng giá trị đã chốt, mã `00` |
| WB → ID | Register file trả trực tiếp dữ liệu đang được phép ghi nếu cổng đọc trùng `rd`; x0 luôn bằng 0 |

Mỗi toán hạng có mux riêng. Nếu MEM và WB cùng khớp, MEM thắng vì chứa
giá trị mới hơn. Giá trị rs2 sau mux được dùng cho ALU/so sánh nhánh và
dữ liệu store, kể cả khi toán hạng B của ALU chọn immediate.

Trong MEM chờ, WB cũ có thể rời pipeline trước lệnh đang đứng tại EX.
Vì vậy top chốt `ex_rs1_value`, `ex_rs2_value` trở lại hai thanh ghi dữ
liệu ID/EX ở mỗi cạnh chờ. Khi MEM/WB mất `valid`, EX vẫn có giá trị đúng.
Không hiểu “giữ ID/EX” thành “mọi bit ID/EX đều bất biến”.

## 6. Hai giao thức bộ nhớ khác nhau

Các cột dưới đây là giá trị lấy mẫu **ngay trước cạnh lên**; cập nhật thanh
ghi có hiệu lực sau cạnh đó. Dấu `—` nghĩa là không cần xét payload.

Ví dụ lấy một lệnh tại A, có một cạnh chờ grant:

| Tín hiệu / cạnh | N | N+1 | N+2 |
|---|---|---|---|
| `imem_req_o` | 1 | 1 | 1 |
| `imem_addr_o` | A | A | A+4 |
| `imem_gnt_i` | 0 | 1 | 1 |
| `imem_rvalid_i` | 0 | 0 | 1 |
| `imem_rdata_i`, `imem_err_i` | — | — | lệnh tại A, 0 |
| Ý nghĩa | Giữ yêu cầu | Nhận yêu cầu A | Nhận A+4, đưa đáp ứng A vào FIFO |

Cột N+2 minh họa grant yêu cầu tiếp theo đồng thời đáp ứng A, khi còn chỗ
và không có sự kiện chặn. Đáp ứng cho một yêu cầu mới không được về ngay
ở cùng cạnh grant. `rvalid` độc lập với `req`, không có `rready`.

IF dành trước chỗ bằng `frontend_used = fifo_count_q + req_count_q +
req_hold_valid_q`, tối đa hai. Yêu cầu đang chờ grant cũng chiếm chỗ.
ID lấy đầu FIFO cùng cạnh cho phép phát yêu cầu mới khi hai chỗ đang đầy.
Đáp ứng đúng đường chuyển một chỗ từ hàng đợi yêu cầu sang FIFO; đáp ứng
bị hủy chỉ giải phóng chỗ trong hàng đợi yêu cầu.

Redirect xóa FIFO và đặt cờ `kill` cho yêu cầu cũ. Yêu cầu chưa grant vẫn
giữ địa chỉ cũ tới grant; đáp ứng cũ vẫn được nhận để trả chỗ nhưng không
đưa vào ID, kể cả đáp ứng báo lỗi. Cờ `kill` giữ qua nhiều lần redirect.
Lỗi fetch đúng đường tạo `{pc=A, instr=0, exc_valid=1, cause=1}` trong FIFO
và dừng phát mới; nhánh già hơn vẫn có thể loại phần tử lỗi này.

Ví dụ giao dịch dữ liệu có hai cạnh chờ, với `P={we,addr,wdata,wstrb}`:

| Tín hiệu / cạnh | N | N+1 | N+2 |
|---|---|---|---|
| `dmem_req_o` | 1 | 1 | 1 |
| Payload | P | P | P |
| `dmem_ready_i` | 0 | 0 | 1 |
| `dmem_err_i` | — | — | E |
| Ý nghĩa | Giữ MEM | Giữ MEM | Hoàn tất và đưa lệnh/kết quả lỗi vào MEM/WB |

Nếu `E=0`, load lấy dữ liệu và lệnh có thể hoàn tất tại WB ở cạnh N+3.
Nếu `E=1`, `mem_fault_event=1` tại N+2, lệnh trẻ hơn bị xóa; WB chốt trap
tại N+3 và không ghi kết quả load. `err` khi `ready=0` bị bỏ qua. Data bus
không có grant riêng và có thể trả `ready` ngay chu kỳ đầu phát yêu cầu.
Đây là thời điểm core xác nhận hoàn tất; thời điểm ghi vật lý bên slave
tuân theo [đặc tả tích hợp](giao_tiep_rtl_vi.md), không suy ra chỉ từ trace WB.

## 7. Mở dạng sóng và tìm đúng tệp

Bắt đầu với `clk_i`, `rst_i`, bốn nhóm `*_valid_q/pc_q/instr_q`,
`mem_stall`, `load_use_stall`, các `*_event`, `retire_*` và `trap_*`.
Theo PC của một lệnh từ trái sang phải trước khi xem toàn bộ dữ liệu.
`debug_fetch_pc_o` là PC dành cho yêu cầu mới; khi chờ grant, nó có thể
khác `imem_addr_o`, và không phải PC lệnh vừa hoàn tất.

| Dấu hiệu cần xem | Bổ sung tín hiệu | Tệp RTL / kiểm thử liên quan |
|---|---|---|
| Sai toán hạng, store ghi sai dữ liệu | `forward_rs*_sel`, `ex_rs*_value`, `idex_rs*_data_q`, `memwb_wb_data_q` | [hazard](../rtl/core/control/rv32_hazard_unit.v), [core](../rtl/core/rv32_core.v); [tb_rv32_core](../tb/core/tb_rv32_core.v) |
| Lệnh hoàn tất lặp khi bus chờ | `dmem_req_o`, `dmem_ready_i`, `memwb_valid_q`, `retire_valid_o` | [core](../rtl/core/rv32_core.v), [WB](../rtl/core/wb/rv32_wb_stage.v); [tb_rv32_core](../tb/core/tb_rv32_core.v) |
| Mất lệnh hoặc tràn chỗ IF | `request_accept`, `response_pop`, `fifo_pop`, ba bộ đếm/chỉ báo chỗ | [IF](../rtl/core/if/rv32_if_stage.v); [tb_rv32_if_stage](../tb/core/if/tb_rv32_if_stage.v), [tb_rv32_core_fetch](../tb/core/tb_rv32_core_fetch.v) |
| Lỗi sai đường trở thành trap | `ex_redirect_event`, `req_kill*_q`, `response_live`, `ifid_exc_valid_q` | [IF](../rtl/core/if/rv32_if_stage.v), [điều khiển](../rtl/core/control/rv32_pipeline_control.v); [tb_rv32_core_ordering](../tb/core/tb_rv32_core_ordering.v) |
| Sai cause hoặc sai lệnh bị trap | `*_exc_valid_q`, `*_exc_cause_q`, `mem_fault_event`, `wb_trap_event`, `trap_pc_o` | [ID](../rtl/core/id/rv32_id_stage.v), [EX](../rtl/core/ex/rv32_ex_stage.v), [MEM](../rtl/core/mem/rv32_mem_stage.v); [tb_rv32_core_traps](../tb/core/tb_rv32_core_traps.v), [tb_rv32_core_ordering](../tb/core/tb_rv32_core_ordering.v) |

Tên kiểm thử trong bảng là nơi bắt đầu đọc hoặc tái hiện tình huống;
bảng không tuyên bố các kiểm thử đã chạy trong một lần sửa cụ thể.
