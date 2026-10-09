# External ISA verification source

`riscv-tests/` is an unmodified shallow checkout of
https://github.com/riscv-software-src/riscv-tests at
`bcffa2b3188b040c611f90dc0b6e422f54775a09`.

The upstream `LICENSE` remains in that directory. No external RTL is imported.
Only RV32UI assembly and scalar test macros are used. The local trap-and-halt
adapter is in `tb/core/isa/env`; tests are built with `-march=rv32i -mabi=ilp32`.

To restore a missing checkout, clone the repository here and checkout the exact
commit above. `scripts/run_isa.py` verifies the revision and rejects modifications
to tracked ISA source. It does not download anything automatically.
