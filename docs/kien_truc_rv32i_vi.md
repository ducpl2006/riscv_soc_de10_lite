# Kiến trúc core RV32I pipeline 5 tầng

Mã nguồn đã tách thành năm module tầng trong `rtl/core/if`, `id`, `ex`, `mem`,
`wb`; điều khiển chung ở `control`. Sơ đồ file, ownership thanh ghi pipeline và
contract tích hợp xem [đặc tả hiện tại](dac_ta_core_bus_ngoai_vi.md).

## 1. Mục tiêu thiết kế

Thiết kế chọn pipeline 5 tầng cổ điển vì nó tách đường tổ hợp dài của một core
single-cycle thành các phần có trách nhiệm rõ ràng. Đây là baseline phù hợp để
học kiến trúc CPU nhưng vẫn giữ các nguyên tắc cần có khi đưa lên FPGA:

- thanh ghi kiến trúc chỉ ghi tại WB; store thực hiện trong giao dịch MEM;
- request bộ nhớ không bị mất khi slave chèn wait-state;
- phụ thuộc dữ liệu được xử lý bằng forwarding và stall có chủ đích;
- control hazard luôn flush lệnh sai đường;
- ngoại lệ không cho lệnh trẻ hơn tạo side effect.

Core là in-order, single-issue: tối đa một lệnh mới vào pipeline mỗi chu kỳ và
thứ tự retire giống thứ tự chương trình.

## 2. Luồng dữ liệu tổng quát

```text
 Instruction bus
       |
       v
 +-----+-----+   IF/ID   +---------+   ID/EX   +---------+
 |    IF     |---------->|   ID    |---------->|   EX    |
 | request   |           | decode  |           | ALU/BR  |
 +-----------+           | regfile |           +----+----+
                         +---------+                |
                                                    | EX/MEM
                                                    v
                         +---------+   MEM/WB  +----+----+
 Register file <---------|   WB    |<----------|   MEM   |<--> Data bus
                         | commit  |           | LSU/bus |
                         +---------+           +---------+

 Forwarding: EX/MEM -----> EX, MEM/WB -----> EX, WB -----> ID
 Control:    EX redirect --flush--> IF/ID và ID/EX
```

Các thanh ghi pipeline mang cả dữ liệu lẫn metadata: `valid`, PC, instruction,
địa chỉ register, control write-back và thông tin exception. Cờ `valid` là cơ
chế bubble chính; dữ liệu trong một stage không có ý nghĩa khi `valid=0`.

## 3. Từng tầng pipeline

### IF — Instruction Fetch

IF quản lý `fetch_pc_q` và giao tiếp với instruction memory bằng hai kênh độc
lập:

1. Kênh request: địa chỉ được chấp nhận tại cạnh có
   `imem_req_o && imem_gnt_i`. Nếu chưa có `gnt`, core giữ nguyên `req` và
   `addr` cho tới khi request được chấp nhận hoặc reset.
2. Kênh response: `imem_rvalid_i` báo một response hợp lệ; `imem_rdata_i` và
   `imem_err_i` chỉ có nghĩa trong chu kỳ đó. Response phải về đúng thứ tự đã
   nhận request.

Frontend quản lý tối đa hai instruction tính trên tổng số request đang chờ và
response đã nằm trong FIFO. FIFO depth 2 cho phép instruction memory latency một
chu kỳ vừa trả response hiện tại vừa nhận địa chỉ kế tiếp, vì vậy ID có thể nhận
một instruction mỗi chu kỳ khi không có hazard hoặc redirect.

Mỗi request được gắn PC và cờ hủy riêng. Redirect xóa FIFO, đánh dấu hủy các
request cũ nhưng vẫn nhận/bỏ response theo đúng hợp đồng bus. Cờ hủy giữ tới
khi giao dịch kết thúc; nhiều lần redirect không làm request cũ sống lại.
Request đã đặt nhưng chưa được `gnt` vẫn giữ ổn định, sau khi được nhận cũng bị
đánh dấu sai đường. Reset là ngoại lệ duy nhất được phép hủy request chưa được
grant. Core và memory phải reset đồng thời; bus không có ID nên không thể
nhận diện đáp ứng trước reset nếu nó đến sau khi đã có request mới.
Chi tiết tại [đặc tả giao tiếp RTL](giao_tiep_rtl_vi.md).

### ID — Decode và đọc register

Decoder kiểm tra opcode, `funct3`, `funct7` một cách nghiêm ngặt. Một encoding
không thuộc RV32I baseline không được biến thành NOP âm thầm; nó mang exception
`illegal instruction` xuống pipeline.

Register file có hai cổng đọc tổ hợp, một cổng ghi đồng bộ và x0 hard-wired 0.
Bypass WB→ID giải quyết trường hợp lệnh tại WB ghi đúng register mà lệnh tại ID
đang đọc trong cùng chu kỳ.

Decoder còn phát `uses_rs1`/`uses_rs2`. Hai bit này tránh stall giả, ví dụ trường
`instr[24:20]` của `ADDI` là immediate chứ không phải rs2.

### EX — Execute, forwarding và quyết định control flow

Hazard unit chọn toán hạng mới nhất:

1. EX/MEM nếu lệnh trước đang có kết quả ALU/PC+4;
2. MEM/WB nếu kết quả đã tới write-back;
3. dữ liệu đã đọc và chốt trong ID/EX nếu không có phụ thuộc.

ALU thực hiện arithmetic/logic. Branch unit so sánh hai toán hạng đã forwarding.
Target của branch/JAL là `PC + immediate`; target JALR là
`(rs1 + immediate) & ~1`. Bộ cộng ALU được tái sử dụng để tính target, không
cần bộ cộng PC/rs1 riêng. Vì baseline không có extension C, target hợp lệ phải
chia hết cho 4.

Branch/jump được giải quyết ở EX. Nếu taken, IF/ID và ID/EX là lệnh sai đường và
bị đổi thành bubble; `fetch_pc_q` nhận target.

### MEM — Load/store và data bus

LSU nhận địa chỉ byte hiệu dụng từ ALU. Bus ngoài rộng 32 bit nên LSU:

- căn `dmem_addr_o` xuống biên word;
- dịch store data vào đúng byte lane;
- tạo `dmem_wstrb_o[3:0]`;
- chọn byte/halfword từ read word và sign/zero extend khi load.

EX/MEM được giữ nguyên khi `dmem_ready_i=0`; do đó toàn bộ request data bus cũng
ổn định khi đang có giao dịch. Các stage trước MEM dừng, nhưng FIFO fetch vẫn
phải nhận các response đã đặt trước credit tại thời điểm phát request. Hai
phần tử FIFO hấp thụ stall ngắn; thiếu credit thì dừng phát request mới,
không được bỏ response hợp lệ chỉ vì ID đang dừng.

### WB — Commit

WB là điểm duy nhất ghi register file và phát `retire_valid_o`. Write-back chọn
một trong ba nguồn:

- kết quả ALU;
- load data đã mở rộng;
- `PC+4` cho JAL/JALR.

Ghi rd=x0 bị chặn. Store, branch và FENCE vẫn retire nhưng
`retire_rd_we_o=0`.

## 4. Data hazard

### ALU dependency: forwarding, không stall

```text
Chu kỳ       1    2    3    4    5    6
ADD x3,...   IF   ID   EX   MEM  WB
SUB x4,x3    .    IF   ID   EX   MEM  WB
                         ^ nhận x3 từ EX/MEM
```

Kết quả ADD có ngay cuối EX nên SUB lấy trực tiếp từ EX/MEM, không chờ register
file.

### Load-use: chèn một bubble

```text
Chu kỳ       1    2    3    4    5    6    7
LW  x3,...   IF   ID   EX   MEM  WB
ADD x4,x3    .    IF   ID   ST   EX   MEM  WB
                            ^ bubble; sau đó forward từ MEM/WB
```

Load data chỉ có sau MEM. Khi load ở EX và lệnh ID thực sự dùng rd của load,
hazard unit giữ IF/ID + fetch PC và làm ID/EX invalid đúng một chu kỳ. Nếu data
bus wait-state, stall MEM tự kéo dài thời gian chờ mà không chèn thêm lệnh.

## 5. Control hazard

Core không dự đoán branch. Branch/JAL/JALR chỉ biết target/taken tại EX nên tối
đa hai lệnh trẻ hơn đã nằm ở ID và IF. Khi redirect:

- lệnh branch/jump vẫn đi tiếp tới MEM/WB và retire;
- ID/EX và IF/ID bị flush;
- fetch response sai đường đang pending được đánh dấu kill;
- lần fetch hợp lệ tiếp theo dùng target.

JAL/JALR ghi `PC+4` dù redirect; forwarding cho phép target code dùng link
register ngay khi cần.

## 6. Ngoại lệ precise

Mỗi stage có `exc_valid` và `exc_cause`. Khi phát hiện fault:

- instruction gây fault tiếp tục đi xuống pipeline nhưng mọi side effect bị khóa;
- các instruction trẻ hơn bị flush và front-end ngừng phát request mới;
- instruction già hơn vẫn được phép hoàn tất;
- chỉ khi fault tới WB, core đặt `trap_valid_o`, chốt cause/PC/instruction và halt.

Thứ tự ưu tiên trong cùng chu kỳ là stage già hơn trước: MEM fault thắng EX
redirect/fault; EX thắng ID; ID thắng fetch. Nhờ vậy exception sai đường phía sau
một branch taken không thể làm core trap.

Các cause được hỗ trợ: instruction address/access fault, illegal, breakpoint,
load/store address/access fault và ECALL. Thiết kế chưa có trap vector/CSR nên
trap là trạng thái halt cho tới reset.

## 7. Reset, endian và alignment

- Reset đồng bộ, active-high; phải giữ qua ít nhất một cạnh clock.
- Little-endian: byte địa chỉ thấp nằm ở bit `[7:0]` của word.
- Instruction phải căn 4 byte vì không có C extension.
- LH/LHU/SH căn 2 byte; LW/SW căn 4 byte; byte access không cần căn.
- Truy cập misaligned không được tách thành hai transaction.

## 8. Giới hạn và hướng mở rộng

Baseline chưa có CSR/trap handler, interrupt, counter, cache, PMP, debug module,
extension M/A/C hoặc bus chuẩn AXI/Avalon/Wishbone. Nên đạt regression hiện tại
và RISC-V architectural tests trước khi thêm pipeline sâu hơn hay cache.
