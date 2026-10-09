/* Bare-metal adapter only. Upstream instruction tests/macros stay unchanged.
 * No privilege setup, CSR, MRET, tohost or trap handler is needed by this core.
 * a0=1 + EBREAK at rvtest_pass means PASS; a0=0 means FAIL, gp is TESTNUM.
 */
#ifndef SOC_RISCV_TEST_H
#define SOC_RISCV_TEST_H
#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp
#define RVTEST_CODE_BEGIN .section .text.init; .globl _start; .option norvc; .option norelax; _start:
#define RVTEST_CODE_END
#define RVTEST_PASS li a0,1; .globl rvtest_pass; rvtest_pass: ebreak; j rvtest_pass
#define RVTEST_FAIL li a0,0; ebreak; j .
#define RVTEST_DATA_BEGIN .balign 16; .globl begin_signature; begin_signature:
#define RVTEST_DATA_END .balign 16; .globl end_signature; end_signature:
#endif
