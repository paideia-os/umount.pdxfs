# umount.pdxfs — architecture

**Wave:** R53 tool (design/tooling/volume-tooling-ux.md §2.3 + §5 + §9.3)
**Repo:** github.com/paideia-os/umount.pdxfs
**Upstream design:** `design/tooling/volume-tooling-ux.md` §5 (CLI spec)
+ §9.3 (milestone breakdown) and
`design/tooling/volume-lifecycle-mechanism.md` (WAL clean-checkpoint
sequence, needed from M2 onward) in
[paideia-os](https://github.com/paideia-os/paideia-os).

This document describes the internal shape of `umount.pdxfs`. It does
not repeat the wave-level rationale from the paideia-os plan doc; read
that first for why volume tooling needs three CLIs plus one shared
library (`libpdx-volume`) and for the R52/R53 boundary (R52 = in-kernel
substrate, R53 = user-facing path to format/mount/unmount).

## 1. What this tool is

`umount.pdxfs` is a standalone ring-3 ELF — a `_start`-based executable,
**not** a shared library like `libpdx-volume` or `libpdx-audit`. It
performs its own syscalls directly (self-contained inlined-syscall
pattern), matching the `src/user/true.pdx` / `cat.pdx` / `mkdir.pdx`
convention in the paideia-os monorepo and `mkfs.pdxfs`'s own landing in
this repo family, rather than delegating every kernel touch to a linked
library. The one library it will link, `libpdx-volume`, supplies
mount-table row parsing/snapshotting — not process lifecycle, argv, or
output.

`umount.pdxfs` resolves a `<mount-id | mount-point>` target to a
mount-table row, drives the volume's WAL through a clean-checkpoint
transition, and removes the row — per
`design/tooling/volume-tooling-ux.md` §5. It is the reversal of
`mount.pdxfs`, and (transitively, via the mounted volume) of
`mkfs.pdxfs`.

## 2. Module split

Four source files, one per major concern (matches `mkfs.pdxfs`'s and
`libpdx-audit`'s own "one module per public-entry-point family"
granularity):

- **`src/main.pdx`** (`Main`) — `_start`. Wires argv parsing → the M1
  dry-run emit path, or falls through to a `not yet implemented`
  diagnostic. Owns the `ParsedArgv` scratch struct's storage
  (`umnt_argv_out`, `.bss`) and the two fd-2 diagnostic message
  literals.
- **`src/argv.pdx`** (`Argv`) — the long-flag CLI parser (`argv_parse`)
  plus the one pure-leaf helper it calls (`argv_streq`). Owns the
  `ParsedArgv` out-struct layout constants (`PA_OFF_*`, `PA_FLAG_*`) and
  every flag literal. Simpler than `mkfs.pdxfs`'s own `argv.pdx`: all
  four flags (`--lazy`, `--force`, `--verbose`, `--dry-run`) are exact
  boolean matches, so this file needs no `argv_prefix_match` (no
  value-flags in umount's argv surface) and no `argv_parse_u64_dec` (the
  `<mount-id | mount-point>` positional is stored as a raw string
  pointer at M1; distinguishing an integer mount-id from a path is
  `umount.pdxfs.M2-001`'s job, not argv parsing's).
- **`src/unmount_record.pdx`** (`UnmountRecord`) —
  `unmount_record_emit_dry_run`, the M1 `PdxFsUnmountRecord@0.1`
  line-based text emitter, plus its own private
  `unmount_record_strlen` helper.
- **`src/elevate.pdx`** (`Elevate`) — placeholder for the future
  `--force` elevate gate (§5.2 + §8.2). No live entry point at M1; see
  §6 below and the file's own module header for the M3-002 landing
  plan.

Kept as four separate files rather than one `main.pdx` monolith for the
same reason `mkfs.pdxfs` gives: each has a distinct, independently-
testable contract that grows independently at later milestones — `argv.
pdx` potentially replaced wholesale by a `libpdx-argv`-backed rewrite,
`unmount_record.pdx` growing the full 15-field semantic-pipe emit at
M3-003, `elevate.pdx` growing its first live body at M3-002 — none of
which should require touching the other three files. Unlike
`mkfs.pdxfs`, this repo has no `target.pdx` at M1: umount's positional
needs no M1-scoped byte-prefix classifier the way mkfs's file-vs-
device-cap split does, since M1's `--dry-run` path prints unconditionally
(§4 below).

## 3. `libpdx-argv` / `libpdx-elevate` availability — confirmed absent, minimal/deferred instead

Issue #2's own instruction was to check whether `libpdx-argv` exists
(either in the paideia-os monorepo or under `paideia-satellites/`) and
wire against it if so. A `grep -rl libpdx-argv` across both trees at
this landing's time finds **zero implementation files** — the same
result `mkfs.pdxfs`'s own M1-002 found — only design-doc *mentions* of a
planned library (`design/tooling/r49-r50-plan.md` §3.2). Per the same
fallback instruction `mkfs.pdxfs` followed, `src/argv.pdx` implements a
**minimal long-flag parser inline**. `Argv::argv_parse` takes `(argc,
argv, out_ptr)` and returns a status code, writing a 16-byte
`ParsedArgv` struct (two u64-aligned slots: `flags`, `target_ptr`) to
`out_ptr` — deliberately the same shape a future `libpdx-argv`-backed
rewrite would present.

`libpdx-elevate` has the identical "design-doc-mentioned, not yet
bootstrapped" status: no repo or source file exists under
`paideia-satellites/` implementing it. Unlike `libpdx-argv`, this repo
does **not** ship a minimal inline fallback for it at M1 — `--force`'s
elevate gate is not reachable from any M1 code path (main.pdx parses
the flag into `ParsedArgv.flags` but never branches on it), so there is
nothing for an inline fallback to serve yet. `src/elevate.pdx` records
the deferral and names `umount.pdxfs.M3-002` as the issue that must
either link a real `libpdx-elevate` or decide, at that time, whether a
minimal inline fallback (mirroring `argv.pdx`'s own posture) is the
right call.

## 4. `PdxFsUnmountRecord@0.1` — what M1 actually prints

`design/tooling/volume-tooling-ux.md` §5.6 defines the full 15-field
schema (`audit_id`, `mount_id`, `volume_uuid`, `mount_point`,
`invoker_user`, `dirty_pages_flushed`, `txns_drained`, `journal_state`,
`result_code`, `open_handles`, `revoked_handles`, `deferred`, `ts_ns`).
This issue's own acceptance text asks for a much smaller slice:

```
PdxFsUnmountRecord@0.1 { target: <target>, flags: <flags>, result_code: DRY_RUN }
```

`src/unmount_record.pdx`'s `unmount_record_emit_dry_run` prints exactly
this three-field line, via a fixed sequence of `sys_write(1, ...)` calls
(literal chunk, then dynamic value, repeated) — no schema-registry
binding, no `KIND_IPC_ENDPOINT` framing. `target` is the caller's actual
raw `<mount-id | mount-point>` argv string; `flags` is a real decimal
conversion of the caller's actual `ParsedArgv.flags` bitmask.
`result_code` is always the literal `DRY_RUN` — this module has no
other caller at M1.

Note that `flags` is **not** itself a field the real §5.6 schema
defines — it is this M1 landing's own task-scoped rendering of the
argv bitmask, standing in for the fields that argv flag will eventually
drive (`--lazy` → a `PENDING` `result_code` + later `DEFERRED` record,
§5.4; `--force` → `revoked_handles` population, §5.3). The real M3-003
semantic-pipe emit does not carry a `flags` wire field forward; it
carries the real fields those flags cause.

## 5. `main.pdx`'s M1 dispatch — no target-classification gate

Unlike `mkfs.pdxfs`, which gates its `--dry-run` happy path on
`target_classify` returning `TARGET_FILE` (its target is either a
filesystem path or a `cap:blkdev:` URI — genuinely different resolution
paths at M2/M3), `umount.pdxfs`'s `<mount-id | mount-point>` positional
has no M1-relevant taxonomy split: both forms feed the same
`mount_table_snapshot`-based resolution at `umount.pdxfs.M2-001`, and
this issue's own acceptance text asks for the dry-run record to print
whenever `--dry-run` is given, regardless of the target's shape. `main.
pdx`'s `_start` therefore has exactly one gate (is `PA_FLAG_DRY_RUN`
set?), not two — there is no `target.pdx` in this repo's M1 `src/`
tree.

## 6. `Elevate` module — deliberately inert at M1

`src/elevate.pdx` declares a module with a single documentation
constant (`KIND_ELEVATE_CHANNEL_REF`) and no executable function. This
is a stronger form of "placeholder" than `mkfs.pdxfs`'s own `KIND_SIG_
KEY` mention in its `caps.decl` (which is a comment, not a file):
`elevate.pdx` exists as a real, buildable module so that a reader of
`src/` finds the future `--force` elevate entry point's home without
cross-referencing `caps.decl`, while carrying zero risk of dead-code or
register-discipline mistakes in a function nothing calls yet. The real
body — `elevate_request_force_unmount(mount_point_ptr) -> u64` — lands
at `umount.pdxfs.M3-002` once `main.pdx` actually branches on
`PA_FLAG_FORCE`.

## 7. `KIND_VOLUME` op-catalog gap (flagged for main)

`caps.decl` documents this in full; summarized here for visibility.
`design/tooling/volume-tooling-ux.md` §5.2 labels the rights this tool
needs on the resolved `KIND_VOLUME` cap as "flush+unmount". The kind's
**real, landed** op catalog — per `libpdx-volume`'s own `caps.decl` in
`paideia-satellites/libpdx-volume` — is `VOL_OP_QUERY_*` +
`VOL_OP_DEBUG_PRINT` (ordinals 0..9, `VK_OPS_VALID_MASK = 0x3FF`); there
is no landed "unmount" op, and §5.3's own `VOL_OP_QUERY_HANDLE_COUNT` is
explicitly described in the design doc's own prose as "a new op added
by R53.M2" — i.e. not yet landed kernel-side as of this M1 landing. This
mirrors the exact shape of the `KIND_BLOCK_DEVICE` naming gap
`mkfs.pdxfs`'s own `caps.decl` / `design/architecture.md` §6 flags for
main, and the `KIND_PDXFS_MOUNT_TABLE` discrepancy `libpdx-volume`'s own
`design/architecture.md` §4 flags. **Confirm with osarch before
`umount.pdxfs.M2-002`** (handle-count query) and **M2-003** (cache-flush
+ checkpoint path) implement a real cap-invoke against either op.

## 8. Register-preservation discipline (a correctness note, not upstream-sourced)

Every public entry point in this repo that repurposes a SysV
callee-save register (`rbx`, `r12`-`r15`) for cross-syscall or
cross-nested-call state explicitly `push`es it on entry and `pop`s it
(in reverse order) immediately before its `ret` — `Argv::argv_parse` (5
registers) and `UnmountRecord::unmount_record_emit_dry_run` (2
registers) both do this. This matches the discipline `mkfs.pdxfs`'s own
`Argv::argv_parse` / `FormatRecord::format_record_emit_dry_run` and
`libpdx-audit`'s `audit_send_record` follow. Every pure-leaf helper in
this repo (`argv_streq`, `unmount_record_strlen`) touches only
caller-save registers and needs no push/pop.

## 9. What M1 explicitly does not do

Called out here so a reader of M1 code does not mistake absence for
bug:

- No mount-point → mount_id resolution — `<target>` is stored and
  printed as a raw string; `umount.pdxfs.M2-001`.
- No handle-count query, no `IN_USE` refusal — `umount.pdxfs.M2-002`.
- No cache flush, no txn drain, no checkpoint, no superblock
  re-sign+rewrite, no mount-table row removal — all `umount.pdxfs.M2-003`.
- No `--lazy` semantics (`PENDING_UNMOUNT`, `DEFERRED` completion
  record) — `umount.pdxfs.M3-001`. The flag is parsed into
  `ParsedArgv.flags` but never branched on by `main.pdx`.
- No `--force` semantics (elevate, handle-revoke) — `umount.pdxfs.M3-002`.
  Same "parsed but not branched on" status as `--lazy`.
- No `libpdx-audit` journaling — `umount.pdxfs.M3-003`/M3-004 territory
  per §8.1's audit-first discipline. M1's `--dry-run` path writes
  directly to stdout with no audit-first gate; acceptable at M1 for the
  same reason `mkfs.pdxfs`'s own architecture doc gives: the D3
  audit-first discipline gates *user-visible output of a real
  operation's result*, and M1 performs no real operation.
- No semantic-pipe binary framing — only the three-field text line (§4)
  — `umount.pdxfs.M3-003`.
- No `SIG_KEY_LOCKED` refusal path — `umount.pdxfs.M3-004`.
- No `libpdx-volume` link yet. `libpdx-volume.M1` has landed, but
  nothing in this repo calls into it at M1; the real
  `mount_table_snapshot` call at `umount.pdxfs.M2-001` is this tool's
  first `libpdx-volume` link.

## 10. What M2/M3 need before they can open

- `umount.pdxfs.M2-001` (mount-point resolution) needs
  `libpdx-volume.M2`'s real `mount_table_snapshot` body.
- `umount.pdxfs.M2-002` (handle-count query) needs the `KIND_VOLUME`
  op-catalog gap (§7) resolved with osarch, and the `VOL_OP_QUERY_
  HANDLE_COUNT` op itself landed (per the design doc, an R53.M2
  addition — not confirmed landed as of this M1 caps.decl).
- `umount.pdxfs.M3-002` (`--force` + elevate) needs a `libpdx-elevate`
  implementation to exist, or a decision to ship a minimal inline
  fallback per §3 above.
- `umount.pdxfs.M3-003` (semantic-pipe emit) needs the schema-registry
  service (§7.4 of the design doc) or falls back to text-layer output
  per that section's own contingency note.
