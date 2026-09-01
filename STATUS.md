# umount.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M5 (signed release) — **landed**
**Version:** 1.0.0

See `design/tooling/volume-tooling-ux.md` §9.3 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
full 16-issue breakdown this checklist mirrors.

## Milestone checklist

### M1 — Design + skeleton

- [x] **M1-001** — scaffold + `caps.decl` (`KIND_USER` + `KIND_PDXFS_
      MOUNT_TABLE` + `KIND_VOLUME` + `KIND_ELEVATE_CHANNEL`): landed.
      Four source files (`src/main.pdx`, `src/argv.pdx`,
      `src/unmount_record.pdx`, `src/elevate.pdx`), `caps.decl`,
      `design/architecture.md`. Unlike mkfs.pdxfs's own M1 caps.decl,
      every kind referenced here is an already-landed kernel kind at a
      real ordinal (`KIND_USER = 0x190`, `KIND_PDXFS_MOUNT_TABLE =
      0x1A5`, `KIND_VOLUME = 0x1A0`, `KIND_ELEVATE_CHANNEL = 0x191`) —
      no naming-gap placeholder like mkfs.pdxfs's `KIND_BLOCK_DEVICE`.
      `caps.decl` does flag one op-catalog gap: `KIND_VOLUME`'s "flush+
      unmount" rights label (design doc §5.2) has no landed "unmount"
      op yet, and §5.3's `VOL_OP_QUERY_HANDLE_COUNT` is itself
      documented as an R53.M2 addition — confirm the op numbering with
      osarch before M2-002/M2-003 cap-invoke against either.
- [x] **M1-002** — argv surface (`--lazy`, `--force`, `--verbose`,
      `--dry-run`, `<mount-id | mount-point>`): landed. `libpdx-argv`
      does not exist anywhere in the paideia-os monorepo or under
      `paideia-satellites/` as of this landing (confirmed via `grep`,
      same finding mkfs.pdxfs's own M1-002 made) — `src/argv.pdx`
      implements a minimal long-flag parser inline instead. Simpler
      than mkfs.pdxfs's own argv.pdx: all four flags are exact boolean
      matches (`argv_streq` only), no value-flags (`--xxx=`), so no
      `argv_prefix_match` or decimal parser is needed at M1. See
      `design/architecture.md` §3 for the deferral note.
- [x] **M1-003** — first runnable: `umount.pdxfs --dry-run /mnt/foo`
      prints the `PdxFsUnmountRecord@0.1` line it would emit: landed.
      `src/main.pdx`'s `_start` wires `Argv::argv_parse` →
      `UnmountRecord::unmount_record_emit_dry_run` directly — no
      target-classification gate (unlike mkfs.pdxfs, umount.pdxfs's
      positional has no M1 file-vs-device split; mount-id-vs-path
      resolution is M2-001). The printed record is a real rendering of
      the caller's actual target string and flags bitmask, not a
      placeholder-value stub — see `src/unmount_record.pdx`'s module
      header for exactly which of the full 15-field
      `PdxFsUnmountRecord@0.1` schema (§5.6) this M1 slice covers
      (three fields: `target`, `flags`, `result_code`) and note that
      `flags` itself is not a real §5.6 schema field — it is this M1
      landing's own task-scoped rendering of `ParsedArgv.flags`.

### M2 — Core implementation

- [x] **M2-001** (#4) — mount-point → mount_id resolution via
      `libpdx-volume.mount_table_snapshot`: landed. New
      `src/target_resolve.pdx`. A decimal-digit-leading target parses
      directly as the mount_id (confirmed to equal `_mount_table[]`'s
      own slot index, per `sys_mount.pdx`'s return-value contract — no
      separate mount_id allocator exists kernel-side). A non-numeric
      target (a path) calls `mount_table_snapshot` for real against a
      deliberately all-zero local row scratch — no ambient cap-slot
      convention exists for this ring-3 tool to obtain a live
      `KIND_PDXFS_MOUNT_TABLE` row, and even a real row's decoded
      per-slot layout (`mountpoint_vnode_idx`/`root_vnode_idx`/
      `backend_type`/`flags`/`_reserved`) has no field a path STRING
      could be compared against — confirmed via `mount_table_snapshot`'s
      own module header, which independently flags this exact
      discrepancy. Every path-shaped target therefore resolves to
      `TR_ERR_MOUNT_NOT_FOUND` at M2 (a real, safe, deterministic call
      and a real deterministic result — not a fabricated bypass);
      mount-id-shaped targets resolve fully. See
      `src/target_resolve.pdx`'s own module header for the full
      write-up, including a second, independent finding —
      `mount_table_snapshot`'s decode loop dereferences a KERNEL VA
      that is unsafe to touch from ring 3 under this kernel's KPTI
      model, which is why this landing never passes it a real row.
- [x] **M2-002** (#5) — `KIND_VOLUME.VOL_OP_QUERY_HANDLE_COUNT` wiring +
      `IN_USE` refusal (exit 5): landed as a documented HARD STUB. New
      `src/handle_check.pdx`. Confirmed via direct grep of
      `kind_volume.pdx`: `VOL_OP_MAX` is still 9 (0..9,
      `VOL_OP_QUERY_*` + `VOL_OP_DEBUG_PRINT` only) — the op has not
      landed. A SECOND, independent gap: the real `_mount_table[]`
      per-slot layout carries no cap-slot field, so there is no landed
      way to derive which `KIND_VOLUME` cap a resolved `mount_id`
      corresponds to even once the op exists. `handle_check_query`
      always returns 0 (never in use); `handle_check_refuse`'s
      refusal LOGIC is real and live (count > 0 AND !force), just
      structurally unreachable until both gaps close — exactly the
      "refusal check still runs, just never fires" posture this
      issue's own instruction asked for.
- [x] **M2-003** (#6) — non-force happy path: cache flush + txn drain +
      `CLEAN` checkpoint + superblock resign+rewrite + row remove:
      landed. New `src/unmount_op.pdx`. Step 1 (sys_umount) issues the
      REAL syscall (sysno 76, `rdi=mount_id, rsi=flags`) — a genuine
      finding at this landing: the kernel BODY
      (`sys_umount.pdx`, R53.M2-003 #1738) is complete, but
      `dispatch.pdx`'s `dispatch_umount` label was never rewired off
      its original R53.M2-001 (#1736) `-ENOSYS` stub, confirmed by
      direct read of `dispatch.pdx` as of this landing — `sys_umount`
      is unreachable from ring 3 today regardless of caller args. This
      file treats that deterministic `-ENOSYS` as a documented stub
      condition (stub_mask bit 0), not a hard failure, and CONTINUES
      the pipeline — any OTHER negative return is a genuine failure
      that aborts (`UO_RC_KERNEL_ERROR`, remaining steps skipped).
      Steps 2-4 (cache flush/txn drain, CLEAN checkpoint, superblock
      re-sign) and step 5 (row remove) each stub with their own mask
      bit — no `KIND_VOLUME` op name, no userspace-callable checkpoint
      primitive, no in-memory superblock buffer/signing seed available
      to this tool, and no remove-row op in `KIND_PDXFS_MOUNT_TABLE`'s
      real catalog (`PMT_OP_MAX` = 3: LIST/READ_ROW/APPEND_ROW/
      QUERY_SLOT_COUNT) respectively. The overall happy path still
      completes and emits `result_code: OK` with the accumulated
      `stub_mask` in the record's metadata, per this issue's own
      instruction. `main.pdx` now wires all three modules together
      (exit 0 = OK, 3 = MOUNT_NOT_FOUND, 5 = IN_USE, 6 = KERNEL_ERROR);
      `unmount_record.pdx` gained `unmount_record_emit_result` (the
      real five-field emitter) and `unmount_record_write_u64_dec` (a
      shared decimal-conversion helper extracted from the M1 dry-run
      emitter's own inline logic).

Three kernel/library gaps surfaced independently across M2-001/002/003
are flagged for main in full in `caps.decl` and `design/architecture.md`
§7 (updated): (a) no ambient `KIND_PDXFS_MOUNT_TABLE` cap-slot
convention + no path-comparable field in the real per-slot layout +
no remove-row op; (b) `VOL_OP_QUERY_HANDLE_COUNT` unlanded + no
mount_id-to-cap-slot resolution path; (c) `dispatch_umount` unwired to
its own landed body.

### M3 — `--lazy` + `--force` + audit-first + semantic-pipe — **landed**

- [x] **M3-001** (#7) — `--lazy` path: `PENDING_UNMOUNT` flag + `DEFERRED`
      completion record on last handle close. Landed as a documented
      STUB: `src/unmount_op.pdx` gains a `handle_count`-driven gate
      ahead of its six-step pipeline — `handle_count > 0 AND --lazy`
      returns `UO_RC_DEFERRED` (4) with stub bit `UO_STUB_LAZY_
      DEFERRED` (0x20) immediately, with NO follow-up completion
      record ever firing (no kernel-side "last handle closed" callback
      exists to fire one from). `src/handle_check.pdx`'s `handle_check_
      refuse` grows a `lazy_bit` third argument so `--lazy` bypasses the
      up-front IN_USE refusal the same way `--force` already did; the
      real refusal arithmetic is extracted into a new pure leaf,
      `handle_check_decide`, for direct testability. Tested by
      `tests/test_lazy_stub.pdx`.
- [x] **M3-002** (#8) — `--force` path: `libpdx-elevate` + handle-revoke +
      `revoked_handles` list in record. Landed as a FAIL-CLOSED STUB,
      the identical posture and identical missing-broker-cap gap
      `mkfs.pdxfs`'s own M3-005 `elevate_wire.pdx` documents over the
      same (now mature, 4844 LOC) library: `src/elevate.pdx`'s
      `elevate_request_force_unmount` always returns `ELEV_DENY`, so
      `unmount_op` returns `UO_RC_ELEVATION_STUB` (5) with stub bit
      `UO_STUB_ELEVATION_DENIED` (0x40). The `ELEV_GRANT` arm and its
      handle-revoke stub (bit `UO_STUB_HANDLE_REVOKE`, 0x80) are real,
      wired, unreachable code.
- [x] **M3-003 / #9** — semantic-pipe: `PdxFsUnmountRecord@0.1` schema
      bind + emit (`INTENT` + `RESULT` + `DEFERRED`). New `src/audit_
      wire.pdx` (libpdx-audit @0.2's `audit_begin`/`audit_record_
      output`/`audit_commit`, real IPC-send attempts against a
      confirmed-stubbed daemon dispatch, forgiving posture) and new
      `src/pipe_wire.pdx` (libpdx-semantic-pipe fallback — `Registry::
      bind_by_name` confirmed inert per paideia-os#2000, so every
      record stays the M1/M2 line-based `sys_write` rendering behind a
      documented deferral header, identical to `mkfs.pdxfs`'s own
      M3-003 posture).
- [x] **M3-004** (#10) — `SIG_KEY_LOCKED` refusal path (superblock
      cannot be re-signed → refuse without `--force`). Landed as a
      REAL, LIVE gate over an UNREACHABLE condition: `unmount_op`'s
      step 4 now calls `libpdx-volume.pdxb_sign_superblock` for real
      against a placeholder `.bss` buffer + a real non-null all-zero
      seed; the `cmp rax,3309; jne ...` refusal gate is real code, but
      the underlying `MlDsa65::sign` intrinsic only fails on a NULL
      seed pointer — this landing's seed is zero, not unavailable — so
      `UO_RC_SIG_KEY_LOCKED` (6) is unreachable through this call
      chain, per this issue's own "STUB with test noting it"
      instruction.

### M4 — Tests + smoke — **landed**

- [x] **M4-001** (#11) — happy-path smoke: unmount `/mnt` with no open
      handles → volume clean. `tests/test_happy_unmount.pdx` verifies
      the real, syscall-free precondition gate (`handle_check_decide`
      always PROCEEDs at `handle_count == 0`); the syscall-reaching
      pipeline itself (`unmount_op`'s real `sys_umount` attempt) is
      deferred to a future QEMU smoke matrix — a bare test-run cannot
      safely execute a `syscall` instruction, the same constraint
      `libpdx-audit`'s own tests document.
- [x] **M4-002** (#12) — `IN_USE` refusal smoke: open handle blocks
      umount without `--force` / `--lazy`. `tests/test_in_use.pdx`
      exercises `handle_check_decide` directly (four cases) since
      `handle_check_query`'s hard stub makes `HC_REFUSE` unreachable
      through the real query chain.
- [x] **M4-003** (#13) — `--lazy` correctness: `DEFERRED` code emitted.
      `tests/test_lazy_deferred.pdx` (a superset of M3-001's own
      `test_lazy_stub.pdx` — both landed, see tests/README.md for why).
- [x] **M4-004** (#14) — `--force` correctness. `tests/test_force_
      revoke.pdx` asserts `ELEVATION_STUB` (the only reachable outcome
      per the fail-closed elevate stub) — the "OK-with-revoked_
      handles-list" GRANT arm is real but structurally unreachable at
      this landing.

### M5 — Signed release — **landed**

- [x] **M5-001** — dual-signed `manifest.pdxsig` + `CHANGELOG.md` +
      `doc/umount.pdxfs.pdxdoc`. Manifest source form scaffolded with
      every hash and both signature slots as documented placeholders,
      mirroring `libpdx-volume`'s and `libpdx-audit`'s own M5-001
      landings — no live release-line key material lives in this repo.
- [x] **M5-002** — mirror push to `pkgs.paideia-os`, documented in
      `release/RELEASE-1.0.0.md` as a NOT-YET-PERFORMED operator
      runbook (mirror endpoint does not exist as of R53 close, per
      the sibling libraries' own M5 findings).

## Next milestone

M1–M5 are all landed. Follow-up work belongs to new issues, not a
named milestone in this checklist: the three M2 kernel/library gaps
(`VOL_OP_QUERY_HANDLE_COUNT` + mount_id-to-cap-slot resolution,
`dispatch_umount` rewiring, `KIND_PDXFS_MOUNT_TABLE` row-remove op)
remain open and block every stub this tool carries from going real;
a `parent_ep_slot` broker-endpoint cap for `libpdx-elevate` blocks
`--force` ever reaching a real elevation decision; and a real QEMU
smoke matrix (per `tests/README.md`) is needed before the syscall-
reaching happy path and any record emission can be verified
end-to-end.

## Upstream design

`design/tooling/volume-tooling-ux.md` §5 + §9.3 and
`design/tooling/volume-lifecycle-mechanism.md` in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
