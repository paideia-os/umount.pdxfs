# umount.pdxfs — CHANGELOG

## 1.1.2 — 2026-09-02 (ENH-030: libpdx-argv adoption — replaces handwritten scanner)

**Patch bump — no observable behaviour change for well-formed input;
every exit code + stderr diagnostic preserved.** Replaces the
handwritten long-flag scanner in `src/argv.pdx` with a thin wire-in
over paideia-satellites/libpdx-argv v1.1.0 (ENH-030 rename tag). Every
public symbol callers depend on — the `argv_parse` entry point, the
`PA_OFF_*` / `PA_FLAG_*` / `PA_STRUCT_BYTES` constants, and every
`ARGV_ERR_*` return code — keeps its numeric value and its byte
offset unchanged, so `src/main.pdx`'s direct-offset loads at
`[r14 + 0]` / `[r14 + 8]` and every `tests/` [u8; 16] ParsedArgv
buffer continue to work byte-for-byte.

### Added

- **libpdx-argv wire-in** — `argv_parse` now registers the 4
  umount.pdxfs long flags with `flag_spec_register()` (each bound to a
  `FID_*` in the 100..103 range, all `FKIND_BOOL` — this tool has no
  value-carrying flags), drives `parse_argv(argv+8, argc-1)`, then
  walks `flag_ids[0..flag_count)` once to populate the caller's
  16-byte ParsedArgv struct via a linear `cmp r10, FID_*; jne next`
  chain.
- **Flag-name literals** — new NUL-terminated `[u8; N]` names in
  .rodata (`umnt_argv_name_lazy`, `_force`, `_verbose`, `_dry_run`).

### Removed

- **Handwritten scanner** — `argv_streq` and every `argv_lit_*`
  literal deleted. This tool never needed `argv_prefix_match` or
  `argv_parse_u64_dec` (all four flags are booleans), so those two
  helpers were already absent from the pre-shim body.

### Build

- **`bash tools/build.sh --extra-obj-dir ../libpdx-argv/build-out
  ...`** — the standing invocation must now include libpdx-argv's
  build-out alongside libpdx-volume's.

Closes #23 (satellite adoption of libpdx-argv). Depends on
libpdx-argv v1.1.0 (ENH-030 rename).

## 1.1.1 — 2026-09-02 (Phase C: `--extra-archive` + `--gc-sections` for satellite-runtime link)

**Patch bump — additive `tools/build.sh` flag; every existing invocation
still works unchanged.** Wires the two Phase A/B archives from
paideia-os#2226's satellite-runtime-shim landing (paideia-as v0.29.1
`libpaideia_satellite_runtime.a` + libpdx-audit v1.1.1
`libpdx-audit-satellite.a`) through this repo's own final `ld` link so
`bash tools/build.sh --extra-archive .../libpaideia_satellite_runtime.a
--extra-archive .../libpdx-audit-satellite.a` now resolves the
satellite-runtime symbol references (crypto FFI thunks +
`mldsa65_sign_runtime_entry` + `audit_begin` / `audit_commit`
satellite bodies + panic/allocator/eh_personality shim) end-to-end.

### Added

- **`--extra-archive PATH` (repeatable)** on `tools/build.sh`, symmetric
  to the existing `--extra-obj-dir DIR` flag: each PATH is a static
  archive (`.a`) appended to the final `ld` link line AFTER the
  --extra-obj-dir loose objects. Archives are pulled in AS-NEEDED
  (unlike loose objects, which link unconditionally), so the archive
  contents only pay their way for symbols the ELF actually references.
  Bounds-checks the value slot; a bare `--extra-archive` with no
  following PATH exits 2 with `--extra-archive requires an argument`
  (same discipline as `--extra-obj-dir`). A PATH that names a missing
  file surfaces later as an `ld` open-failure at link time (not an
  early parse error) — the flag validates only that the slot was
  supplied, mirroring how `--extra-obj-dir` never validates its DIR.

### Changed

- **`ld` link line** — added `--gc-sections` to the `ld -nostdlib
  --warn-common --fatal-warnings` invocation. Essential when linking
  the Phase A staticlib: Rust archives emit per-function sections
  (`.text.<sym>`), and `--gc-sections` walks from `_start` (KEEPed by
  `link.ld`) and prunes every satellite-runtime symbol nothing in this
  repo transitively references. Without it, the archive dumps unused
  compiler-builtins/std padding into the ELF and leaves dangling refs
  from Rust's own internal call graph. This repo's own `src/*.pdx`
  objects emit into one big `.text` section per module, so
  `--gc-sections` is a no-op for them (the section stays live as soon
  as `_start` is reached).

### Invocation (unchanged for callers not wiring in Phase A/B archives)

```
# Old — still works, still emits build-out/umount.pdxfs.elf against
# just this repo's own objects (dangling refs on satellite-runtime
# symbols surface at ld, not here):
bash tools/build.sh --extra-obj-dir ../libpdx-volume/build-out

# New — resolves every satellite-runtime ref, end-to-end link OK:
bash tools/build.sh \
  --extra-obj-dir ../libpdx-volume/build-out \
  --extra-archive $HOME/Development/PaideiaOS/tools/paideia-as/target/release/libpaideia_satellite_runtime.a \
  --extra-archive $HOME/tmp/libpdx-audit/build-out/libpdx-audit-satellite.a
```

References: paideia-os#2226, paideia-as#1348, libpdx-audit#19, design
doc `design/infrastructure/satellite-runtime-shim.md` §4.1 + §5 Step 5.

## 1.1.0 — 2026-09-02 (libpdx-volume v1.1 API adoption, #21)

**Adoption-only minor release.** Adopts libpdx-volume v1.1 API cleanup
(LV.M1-003 accessors + LV.M1-004 `lpv_strerror` + LV.M1-005 public
consts, libpdx-volume issues #18/#19/#20). No new capabilities, no
wire-format change, no behavior change on any code path -- every
`PdxFsUnmountRecord@0.1` field, every `UR_RC_*` code, every exit
status, every stub-mask bit, and every audit record shape is
byte-for-byte identical to v1.0.0. Cascade parent: umount.pdxfs #21.

### Adopted

- **LV.M1-005 public consts** (libpdx-volume #20). `src/unmount_op.pdx`
  and `src/target_resolve.pdx` now cite the v1.1 public aliases in
  place of bare byte-counts:

  * `PDXB_ONDISK_BYTES` (= 4096) for `umnt_op_sb_scratch`'s
    superblock-shaped `.bss` reserve.
  * `PDXB_SIGN_MSG_LEN` (= 696) for the `out_sig_ptr = sb_ptr + 696`
    pointer arithmetic in the step-4 sign call.
  * `MLDSA65_SIG_LEN` (= 3309) for both the `out_sig_len` argument and
    the success-arm sentinel comparison.
  * `MTE_BYTES` (= 40; v1.1 alias for `MTE_SUMMARY_BYTES`) for
    `umnt_tr_entries_scratch`'s `8 * MTE_BYTES` sizing comment.

  Every immediate stays numeric literal in operand position -- paideia-as
  does not accept const-symbol immediates cross-repo (verified: no such
  usage exists anywhere in libpdx-volume / mkfs.pdxfs / mount.pdxfs /
  umount.pdxfs source trees), matching the family-wide "literal +
  comment cite" convention.

- **LV.M1-003 accessors** (libpdx-volume #18). No call-site rewrite
  landed in this repo: `src/target_resolve.pdx`'s path branch does not
  decode any `MountTableEntry` fields today -- `mount_table_snapshot`'s
  Gate 1 refuses the all-zero row placeholder before the entries
  buffer is ever written (that file's own module header §2, unchanged
  from v1.0.0). The `mte_get_mountpoint_vnode_idx` /
  `mte_get_root_vnode_idx` swap will land alongside the ambient-cap-slot
  gap closure AND the richer per-mount record's arrival (see
  `caps.decl` §KIND_PDXFS_MOUNT_TABLE + `design/architecture.md` §7 for
  both gaps -- neither closed at this release). Module header of
  `target_resolve.pdx` now documents the future-swap plan explicitly.

### Not adopted (documented finding)

- **LV.M1-004 `lpv_strerror`** (libpdx-volume #19). This tool emits no
  human-readable error strings from libpdx-volume codes. Every error
  surfaces through this repo's own `UnmountRecord::UR_RC_*` code space
  (stringified by `src/unmount_record.pdx`'s own literals table) or an
  exit-status integer (see `src/main.pdx`'s per-arm sys_exit table).
  The two cross-repo call sites -- `mount_table_snapshot` in
  `target_resolve.pdx` and `pdxb_sign_superblock` in `unmount_op.pdx`
  -- both discard their return values into repo-local `UR_RC_*`
  buckets (`TR_ERR_MOUNT_NOT_FOUND` / `UO_RC_SIG_KEY_LOCKED`) rather
  than rendering the libpdx-volume code to stderr. Adding a
  `lpv_strerror` diagnostic wire would be additive new behavior, not
  an API cleanup swap, and is out of scope for this adoption-only
  release. Sibling `mount.pdxfs` and `mkfs.pdxfs` cascades DO have a
  natural `lpv_strerror` wire point (their `map_kernel_errno_to_
  result_code` / `refusal` layers surface libpdx-volume codes to
  users); this repo does not.

### Dependency

- `release/manifest.pdxsig.txt`: `libpdx-volume >= 1.0.0` bumped to
  `>= 1.1.0`. Everything ships against libpdx-volume v1.1.1 (the
  latest v1.1.x patch, quota input-contract + arithmetic-wrap guard;
  every v1.1.0 API surface is preserved byte-for-byte at v1.1.1 per
  that repo's own CHANGELOG), but the manifest floor stays at v1.1.0
  since none of the v1.1.1 patches (`pdxb_quota_check` /
  `pdxb_quota_commit` parameter rename + overflow guard) touch any
  code path this tool exercises.

### Build tooling (unchanged from the 2026-09-01 ELF-linking work
### previously staged as Unreleased and now folded into this release)

- **ELF-linking phase.** `tools/build.sh` now links `build-out/*.o`
  (this repo's own `src/*.pdx` objects) into
  `build-out/umount.pdxfs.elf` via `ld -T link.ld`, plus a matching
  `.bin` via `objcopy`, for paideia-os issue #1976/#1977 (satellite-
  tool boot-time `/bin` seeding pipeline). New `link.ld` at repo root
  -- the same `true.ld`-derived layout (`.text`/`.rodata` at
  `0x00400000`, `.data`/`.bss` at `0x00600000`, `.bss` kept contiguous
  with `.data` per paideia-os#1595) every other satellite tool uses.
  `tools/build.sh` also gains a repeatable `--extra-obj-dir DIR` flag
  so a caller (e.g. paideia-os's own build, or a sibling satellite
  repo) can fold in dependency object files at link time; a missing
  or empty directory contributes nothing and is not an error. The
  `tests/*.pdx` objects are never linked.

### Encoder-gap discipline

- No `@no_frame`. No `// No @no_frame` markers. Every new comment
  block uses `// Frame prologue implicit` phrasing where a per-fn
  frame note is warranted; this release adds no new functions and
  extends no existing function bodies, so no such marker is needed.
- No new `add reg, [mem]`. No new `test` mnemonics. Every immediate
  in operand position remains a numeric literal (see LV.M1-005 note
  above); every symbolic constant lives in comments or in a
  library-side `pub let X : u64 = <literal>` binding.

### Not touched at this release

- `caps.decl` (unchanged -- no cap-kind or op catalog change).
- `design/architecture.md` (unchanged -- adoption is a source-comment
  swap, not an architectural move).
- `doc/umount.pdxfs.pdxdoc` (unchanged -- no public-surface change
  visible to `doc umount.pdxfs`).
- `release/RELEASE-1.0.0.md` (kept as the R53 wave-close record;
  cutting a new `RELEASE-1.1.0.md` is out of scope for an adoption-
  only bump and follows main-only precedent whenever the v1.1.0 tag
  is cut).
- Every `tests/test_*.pdx` M4 smoke driver (unchanged -- no wire
  shape moved, so each M4 driver's oracle continues to hold).

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
