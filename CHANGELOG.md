# umount.pdxfs — CHANGELOG

## Unreleased — 2026-09-01

**ELF-linking phase.** `tools/build.sh` now links `build-out/*.o`
(this repo's own `src/*.pdx` objects) into `build-out/umount.pdxfs.elf`
via `ld -T link.ld`, plus a matching `.bin` via `objcopy`, for
paideia-os issue #1976/#1977 (satellite-tool boot-time `/bin` seeding
pipeline). New `link.ld` at repo root — the same `true.ld`-derived
layout (`.text`/`.rodata` at `0x00400000`, `.data`/`.bss` at
`0x00600000`, `.bss` kept contiguous with `.data` per paideia-os#1595)
every other satellite tool uses. `tools/build.sh` also gains a
repeatable `--extra-obj-dir DIR` flag so a caller (e.g. paideia-os's
own build, or a sibling satellite repo) can fold in dependency object
files at link time; a missing or empty directory contributes nothing
and is not an error. The `tests/*.pdx` objects are never linked.

## 1.0.0 — 2026-08-31 (R53 wave close, M5-001)

**First release.** Manifest scaffolded for a future dual-signed
(Ed25519 + ML-DSA-65) release per
`design/02-development-environment.md` §1140 (paideia-os); the actual
dual-sign + mirror-push run is deferred (see "Known deferred substrate"
below). Ships `.pdxdoc` for `doc umount.pdxfs` and a release manifest
source form targeting
`https://pkgs.paideia-os/main/umount.pdxfs/1.0.0/` per
`release/RELEASE-1.0.0.md`.

### Landed

- **M1-001** scaffold + `caps.decl` (`KIND_USER` + `KIND_PDXFS_
  MOUNT_TABLE` + `KIND_VOLUME` + `KIND_ELEVATE_CHANNEL`).
- **M1-002** argv surface (`--lazy`, `--force`, `--verbose`,
  `--dry-run`, `<mount-id | mount-point>`) — minimal inline parser,
  `libpdx-argv` not bootstrapped at landing time.
- **M1-003** first runnable `--dry-run` preview line.
- **M2-001** mount-point → mount_id resolution
  (`TargetResolve::target_resolve`) — real for `<mount-id>` targets
  (confirmed to equal the real `_mount_table[]` slot index); a
  documented dead end for `<mount-point>` targets (no path-comparable
  field exists in the real per-slot layout).
- **M2-002** `KIND_VOLUME.VOL_OP_QUERY_HANDLE_COUNT` wiring + `IN_USE`
  refusal — landed as a documented hard stub (`HandleCheck::
  handle_check_query` always reports 0 handles; the op has not landed
  kernel-side and no mount_id-to-cap-slot resolution path exists).
- **M2-003** non-force happy path: real `sys_umount` syscall attempt
  (observing a documented `-ENOSYS` stub since `dispatch_umount`
  remains unwired to its own landed body) plus four stubbed substeps
  (cache flush, checkpoint, superblock re-sign, row remove).
- **M3-001** `--lazy` path: `DEFERRED` result code, stubbed completion
  (no kernel-side "last handle closed" callback exists). New
  `HandleCheck::handle_check_decide` pure decision leaf.
- **M3-002** `--force` path: fail-closed `libpdx-elevate` elevation
  check (`src/elevate.pdx`, real call, no broker-endpoint cap exists) +
  `ELEVATION_STUB` result code. Handle-revoke and the `ELEV_GRANT` arm
  are real, wired, unreachable code.
- **M3-003** semantic-pipe INTENT + RESULT + DEFERRED emissions. New
  `src/audit_wire.pdx` (real `libpdx-audit @0.2` `audit_begin`/
  `audit_record_output`/`audit_commit` calls against a confirmed-
  stubbed daemon dispatch) and new `src/pipe_wire.pdx` (`libpdx-
  semantic-pipe` fallback — `Registry::bind_by_name` confirmed inert
  per paideia-os#2000; every record stays the line-based `sys_write`
  rendering behind a documented deferral header).
- **M3-004** `SIG_KEY_LOCKED` refusal path — a real, live gate over a
  real `libpdx-volume.pdxb_sign_superblock` call (against a placeholder
  buffer + a real non-null all-zero seed), unreachable at this landing
  since the underlying `MlDsa65::sign` intrinsic only fails on a NULL
  seed pointer.
- **M4-001** happy-path smoke (`tests/test_happy_unmount.pdx`) —
  verifies the real syscall-free precondition gate; the syscall-
  reaching pipeline itself is deferred to a future QEMU smoke matrix.
- **M4-002** `IN_USE` refusal smoke (`tests/test_in_use.pdx`) — a
  four-case matrix against `handle_check_decide`.
- **M4-003** `--lazy` correctness (`tests/test_lazy_deferred.pdx`) — a
  superset of M3-001's own `tests/test_lazy_stub.pdx`.
- **M4-004** `--force` correctness (`tests/test_force_revoke.pdx`) —
  asserts the `ELEVATION_STUB` fail-closed outcome.
- **M5-001** dual-signed release scaffold + `.pdxdoc` + mirror-push
  runbook. Ships `doc/umount.pdxfs.pdxdoc` source form,
  `release/manifest.pdxsig.txt` release-manifest source (every hash
  and signature slot a documented placeholder), and
  `release/RELEASE-1.0.0.md` operator runbook + release note.

### Known deferred substrate

- **`dispatch_umount` unwired.** `src/kernel/core/syscall/
  sys_umount.pdx`'s real body has never been wired into
  `dispatch.pdx`'s `dispatch_umount` label (sysno 76) — confirmed by
  direct read of the kernel source at every M2/M3 landing. `sys_umount`
  is unreachable from ring 3 regardless of caller arguments until a
  one-block `dispatch.pdx` rewrite lands.
- **`VOL_OP_QUERY_HANDLE_COUNT` + mount_id-to-cap-slot resolution.**
  Neither the op nor a way to derive which `KIND_VOLUME` cap a resolved
  `mount_id` corresponds to exists kernel-side. `IN_USE` refusal logic
  is real and live; it never fires through the real query chain.
- **`KIND_PDXFS_MOUNT_TABLE` row-remove op.** `PMT_OP_MAX` = 3
  (LIST/READ_ROW/APPEND_ROW/QUERY_SLOT_COUNT); no remove/delete op
  exists, so step 5 of the unmount pipeline always stubs.
- **`libpdx-elevate` broker-endpoint cap.** No `parent_ep_slot`
  `KIND_IPC_ENDPOINT` cap has been minted for this tool; `--force`'s
  elevation check is permanently fail-closed until one exists.
- **`--lazy` completion callback.** No kernel primitive notifies a
  ring-3 process when a volume's last open handle closes; a `DEFERRED`
  record's promised follow-up completion record can never actually
  fire at this landing.
- **`libpdx-semantic-pipe` schema binding.** `Registry::bind_by_name`
  stays inert until `libpdx-schema-registry` (paideia-os#2000) lands;
  every record stays the line-based fallback rendering.
- **QEMU smoke matrix.** The syscall-reaching happy-path pipeline and
  every record emission need a real kernel to exercise end-to-end;
  `tests/README.md` documents the deferred protocol.
- **Dual-sign + mirror-push run.** Repo-side scaffolding at M5-001 is
  complete. The signed build + push to
  `pkgs.paideia-os/main/umount.pdxfs/1.0.0/` requires a live
  release-line ML-DSA-65 seed key (hardware-backed custody, never
  repo-resident) and a standing mirror endpoint (does not exist as of
  R53 close) — see `release/RELEASE-1.0.0.md` §3.

### Semver policy

- **Major** — wire-format grow past the documented `PdxFsUnmountRecord
  @0.1` fields, exit-code renumber, or any API-surface removal.
- **Minor** — additive functionality (e.g. `dispatch_umount` going
  real, a real `IN_USE` refusal, a real `--lazy`/`--force` completion
  path, a real semantic-pipe schema bind).
- **Patch** — correctness fixes, constant tuning, the deferred
  dual-sign + mirror-push run itself (no repo-side code change).
