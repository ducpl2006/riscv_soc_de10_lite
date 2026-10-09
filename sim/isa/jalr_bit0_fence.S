.option norvc
.option norelax
.section .text.init
.globl _start
_start:

li a0,0
la t0,target
ori t0,t0,1
jalr ra,t0,0
link: j fail
target:
la t1,link
bne ra,t1,fail
bne zero,zero,.+2
li t0,0x8000
li t1,-1
sw t1,0(t0)
fence iorw,iorw
lw t2,0(t0)
bne t1,t2,fail
addi zero,t1,4
bne zero,zero,fail
li a0,1
.globl expected_trap
expected_trap: ebreak
fail: li a0,0
ebreak
