# tests/ — umount.pdxfs test suite (M3 + M4)

**Milestone lineage.** `design/tooling/volume-tooling-ux.md` §9.3
(paideia-os). Five drivers across two milestones in this repo:

- **M3-001 (#7)** — `test_lazy_stub.pdx`, the landing-time smoke check
  for the `--lazy` `DEFERRED` stub (`src/unmount_op.pdx`).
- **M4-002 (#12)** — `test_in_use.pdx`, `IN_USE` refusal correctness.
- **M4-003 (#13)** — `test_lazy_deferred.pdx`, the fuller `--lazy`
  correctness matrix (a superset of #7's own smoke check, exercising
  the up-front `handle_check_decide` bypass too).
- **M4-004 (#14)** — `test_force_revoke.pdx`, `--force` correctness
  (fail-closed elevation denial).
- **M4-001 (#11)** — `test_happy_unmount.pdx`, the happy-path smoke
  check.

Note on file count: the task brief for this landing counts "4 test
files" but separately names five files across #7 and #11-#14
(`test_lazy_stub.pdx` for #7's own M3 landing check, distinct from
#13's `test_lazy_deferred.pdx`). Both are landed here rather than
merging one into the other — they cover genuinely different scope (see
each file's own header) and both issues explicitly name a driver by
that filename. **Flagged for main** in case the "4" was meant to
supersede #7's own driver with #13's.

## Why most drivers never invoke `unmount_op`'s real six-step pipeline

`umount.pdxfs` is a standalone ring-3 ELF, not a shared library — its
functions issue REAL `syscall` instructions
(`sys_umount` at sysno 76 in `src/unmount_op.pdx`'s pipeline,
`sys_write` throughout `src/unmount_record.pdx` / `src/pipe_wire.pdx`,
`sys_getpid` and the IPC send path transitively inside
`libpdx-audit`'s `AuditClient::audit_begin`/`audit_commit`). In a bare
test-run (no kernel, no boot), a `syscall` instruction traps —
identical to the constraint `libpdx-audit`'s own `tests/README.md`
documents for its `sys_ipc_send`-issuing entry points ("in a bare
test-run those calls would trap").

Every driver here therefore stays inside the REAL, syscall-free subset
of this repo's own logic:

- `HandleCheck::handle_check_decide` (pure leaf, no syscall, no cap
  invoke) — the actual `handle_count > 0 AND !force AND !lazy ->
  REFUSE` decision, directly callable with an explicit `handle_count`
  (unlike `handle_check_refuse`, whose own `handle_check_query` call is
  hard-stubbed to always return 0 — see `src/handle_check.pdx`'s module
  header).
- `Elevate::elevate_request_force_unmount` (pure leaf, no syscall, no
  cap invoke) — the fail-closed `--force` elevation stub.
- `UnmountOp::unmount_op`'s new M3 gate (`src/unmount_op.pdx`) — when
  called with `handle_count > 0`, BOTH the `--lazy` `DEFERRED` arm and
  the `--force` `ELEVATION_STUB` arm return BEFORE the function ever
  reaches step 1's `syscall` instruction. This is real, live code
  (not a mock) — the six-step pipeline (steps 1-5, including the real
  `sys_umount` attempt and the real `pdxb_sign_superblock` cross-repo
  call) is simply never entered on either arm, by construction.

## What is deferred to a future QEMU smoke matrix

`unmount_op`'s `handle_count == 0` pipeline (the actual happy/
`KERNEL_ERROR` path, reaching the real `sys_umount` syscall at sysno
76) and every `PdxFsUnmountRecord@0.1` emission (`unmount_record.pdx`'s
`sys_write` calls, reached via `pipe_wire.pdx`) cannot be exercised
from a bare test driver for the reason above. `test_happy_unmount.pdx`
documents this explicitly rather than fabricating a syscall-free
substitute for what is, by definition, a syscall-driven code path — a
future QEMU harness (once one exists for this tool, per `mkfs.pdxfs`'s
and `libpdx-audit`'s own still-deferred M4 QEMU protocols) is where
`umount.pdxfs --dry-run` and a real `umount.pdxfs <mount-id>` end-to-end
run belong.

## Return-code convention

Every driver in this tree exports `run() -> u64` where `0` means "all
subtests passed" and any nonzero value is the 1-based ordinal of the
first subtest that failed. This mirrors `libpdx-audit`'s and
`libpdx-volume`'s own M4 driver convention.

## Why the drivers are not linked into a runnable binary here

Like `mkfs.pdxfs`'s own (still-empty) `tests/` tree, this repo has no
test-runner `main` yet. `tools/build.sh` compiles every `src/*.pdx` and
`tests/*.pdx` file independently; a future consumer (either
`umount.pdxfs` growing a `--self-test` mode, or a shared test-runner
tool) links `src/` alongside these drivers and calls each `run()`.
