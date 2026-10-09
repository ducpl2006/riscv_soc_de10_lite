.option norvc
.option norelax
.section .text.init
.globl _start
_start:
li a0,1
li t2,0xff00
li t1,99
li t0,0x8000
.globl expected_trap
expected_trap:
.word 0
sb t1,0(t2)
ebreak
