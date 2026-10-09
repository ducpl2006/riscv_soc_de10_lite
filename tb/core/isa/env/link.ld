OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0;
  .text : { *(.text.init) *(.text*) }
  . = ALIGN(16);
  .data : { *(.data*) *(.rodata*) }
  .bss : { *(.bss*) *(COMMON) }
  /DISCARD/ : { *(.riscv.attributes) *(.comment) }
  ASSERT(. < 0xF000, "ISA image exceeds test memory")
}
