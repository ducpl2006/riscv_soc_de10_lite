# RV32I frozen baseline

The user froze `rtl/core/**` after ISA verification on 2026-09-27.
See `docs/core_frozen_manifest.json` and `docs/bao_cao_freeze_isa_soc_vi.md`.

- Do not extend or redesign the core, ISA, forwarding, hazards, LSU, exception
  ordering, branch semantics, fetch credits, or wrong-path handling.
- A core change requires a reproducible bug or measured critical timing path,
  with an appropriate test **before** the fix. Preserve all existing tests.
- For a timing experiment, compare at least two options first. Keep a change
  only after full regression and setup/hold/recovery/removal pass; roll back
  improvement below 2 MHz unless there is a clear architectural simplification.
- Run `scripts/check_core_freeze.py` to audit baseline integrity. Do not update
  its manifest merely to silence a mismatch; document the test and justification.
- Current sensor is **INA228**, not INA219. Never assume the board's shunt or
  I2C address. INA228 die temperature is not automatically battery temperature.
- `firmware/build/boot.*` remains the Quartus baseline image. New firmware test
  assets live in `tb/soc/firmware_assets`; do not silently replace the board ROM.

Explicit later user instructions take precedence over this baseline policy.
