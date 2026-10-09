/*
 * Điểm vào bare-metal RV32I.
 * Stack đặt ở cuối SRAM 8 KiB. Không dùng CSR/interrupt vì core hiện chỉ RV32I.
 */
    .section .text.start
    .globl _start
_start:
    lui  sp, 0x10002
    addi sp, sp, -16

    /* Sao chép giá trị khởi tạo .data từ ảnh ROM sang SRAM. */
    la   t0, __data_load_start
    la   t1, __data_start
    la   t2, __data_end
.Lcopy_data:
    bgeu t1, t2, .Lclear_bss_begin
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    .Lcopy_data

    /* C bảo đảm biến static/global chưa khởi tạo bắt đầu bằng 0. */
.Lclear_bss_begin:
    la   t1, __bss_start
    la   t2, __bss_end
.Lclear_bss:
    bgeu t1, t2, .Lcall_main
    sw   zero, 0(t1)
    addi t1, t1, 4
    j    .Lclear_bss

.Lcall_main:
    call main
1:
    ebreak
    j 1b
