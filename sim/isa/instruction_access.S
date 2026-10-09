.option norvc
.option norelax
.section .text.init
.globl _start
_start:
li a0,1
li t0,0x10000
jr t0
ebreak
