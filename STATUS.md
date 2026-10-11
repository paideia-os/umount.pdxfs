# umount.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M5 (signed release) — **landed**
**Version:** 1.1.2 (ENH-030: libpdx-argv adoption — replaces handwritten scanner, #23)

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
      `src/handle_check.pdx`.  **PFS-01 retraction (2026-10-11):** the
      "`VOL_OP_MAX` is still 9, op has not landed" assertion is
      STALE.  Direct source read at `kind_volume.pdx` L189-L190
      confirms `VOL_OP_QUERY_HANDLE_COUNT = 10`, `VOL_OP_MAX = 10`,
      and the dispatch handler at L1161-L1167 WIRES the op (requires
      `R_VOL_INVOKE`, returns 0 as a documented stub body because
      per-row handle-count tracking is a future kernel-side
      enhancement).  **KERNEL ABI frozen at paideia-os commit
      `c49a4bff` per
      [`design/pdxfs/sys-mount-abi.md`](https://github.com/paideia-os/paideia-os/blob/main/design/pdxfs/sys-mount-abi.md)
      §5.3-5.4** — the ABI edge is open; the stub semantics are
      intentional (handle_count==0 → consumers never refuse on
      IN_USE grounds).  The SECOND gap this landing cited
      (mount_id-to-cap-slot resolution absent from `_mount_table[]`
      per-slot layout) remains open — `handle_check_query` cannot
      pass a `KIND_VOLUME` cap slot to `cap_invoke` without resolving
      `mount_id` → volume_cap first.  **PFS-03** adds path-indexed
      slot lookup to libpdx-volume; **PFS-13** wires the real
      `VOL_OP_QUERY_HANDLE_COUNT` call in `handle_check_query` once
      the resolution path lands.  Today's `handle_check_refuse`
      refusal LOGIC is real and live and stays unreachable through
      the real query chain until the kernel-side handle tracking
      lands (post-PFS scope, called out in `sys-mount-abi.md` §7-3).
- [x] **M2-003** (#6) — non-force happy path: cache flush + txn drain +
      `CLEAN` checkpoint + superblock resign+rewrite + row remove:
      landed. New `src/unmount_op.pdx`. Step 1 (sys_umount) issues the
      REAL syscall (sysno 76) — but against the WRONG ABI.  **PFS-01
      retraction (2026-10-11):** the "`dispatch_umount` was never
      rewired off its original R53.M2-001 `-ENOSYS` stub" assertion
      is STALE.  Direct source read at `dispatch.pdx` L2463-L2470
      confirms `dispatch_umount` is a wired shim that reads
      `_current_tcb` into rdi and calls `sys_umount_shim` with
      the path-based ABI (`rsi=path_va, rdx=path_len, rcx=flags`).
      **KERNEL ABI frozen at paideia-os commit `c49a4bff` per
      [`design/pdxfs/sys-mount-abi.md`](https://github.com/paideia-os/paideia-os/blob/main/design/pdxfs/sys-mount-abi.md)
      §3** — not the `rdi=mount_id, rsi=flags` call shape this file
      issued.  The `UO_STUB_UMOUNT_ENOSYS` (bit 0) accommodation this
      landing made for a deterministic `-ENOSYS` is unreachable
      today; what the current call actually produces is an ABI-mismatch
      result that the pipeline treats as `UO_RC_KERNEL_ERROR`.
      **PFS-13 lands the rewrite** (`src/unmount_op.pdx` against the
      frozen path-based `sys_umount_shim` ABI; derives
      `mount_point_va`/`len` from the argv target; `handle_check_query`
      real `VOL_OP_QUERY_HANDLE_COUNT` wire; `PMT_OP_REMOVE_ROW` cap
      invoke).  **PFS-14 closes CLEAN-checkpoint** (cache flush op
      discovery + wire; superblock re-sign real body against PFS-04's
      `mldsa65_verify` cross-repo landing).  Steps 2-4 and step 5
      stub bits each have a PFS-13/PFS-14 close path spelled out in
      [sys-mount-abi.md §5-6](https://github.com/paideia-os/paideia-os/blob/main/design/pdxfs/sys-mount-abi.md).
      Also stale: the "`PMT_OP_MAX = 3`, no remove-row op" bullet —
      direct source read at `kind_pdxfs_mount_table.pdx` L183 confirms
      `PMT_OP_REMOVE_ROW = 4`, `PMT_OP_MAX = 4`, and the dispatch
      handler at L798-L810 WIRES the op (requires `R_PMT_WRITE`,
      stub body returns 0; real per-row removal happens implicitly in
      `umount_pdxfs_block`'s own step 10).  The ABI edge is open.
      `main.pdx`'s wire-up (exit 0 = OK, 3 = MOUNT_NOT_FOUND,
      5 = IN_USE, 6 = KERNEL_ERROR) and the record emitters are
      unchanged by this retraction.

Three kernel/library gaps surfaced independently across M2-001/002/003
are flagged for main in full in `caps.decl` and `design/architecture.md`
§7.  **Of those three, (b) and (c) are RETRACTED per PFS-01**:
`VOL_OP_QUERY_HANDLE_COUNT` is wired (stub body returns 0) and
`dispatch_umount` is wired to the landed body via the path-based ABI.
The remaining real gap is (a) — no ambient `KIND_PDXFS_MOUNT_TABLE`
cap-slot convention + no path-indexed slot lookup helper + the
`PMT_OP_REMOVE_ROW` ABI edge is open-but-stubbed kernel-side.
PFS-02 (cap seed) + PFS-03 (path-indexed lookup) close (a).

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

## Post-M5 follow-up

- [x] **LE-001** (#22) — `/system` elevate gate. `src/target_resolve.
      pdx`'s new `target_is_system` classifies the raw argv target
      string; `src/elevate.pdx`'s new `elevate_request_system_unmount`
      is a SECOND, independent fail-closed elevate stub (distinct from
      M3-002's `--force` gate — this one fires on target classification
      alone, before `handle_check_refuse`/`unmount_op` ever run, so a
      `/system` unmount refuses (`UR_RC_SYSTEM_UNMOUNT_REFUSED`, exit 9)
      with the mount left live even at `handle_count == 0` and neither
      `--force` nor `--lazy` set). Non-`/system` targets and numeric
      `<mount-id>` targets are unaffected (the latter is a real, documented
      scope limit — see `target_is_system`'s own doc comment). Same
      missing-broker-cap blocker as `--force` below.

## Next milestone

M1–M5 are all landed.  Follow-up work is driven by the **PFS AISSUE
wave** (paideia-os PFS-01..PFS-17, filed 2026-10-11).  **KERNEL ABI
frozen at paideia-os commit `c49a4bff` per
`design/pdxfs/sys-mount-abi.md` (PFS-01).**  Ticket map for this
repo's remaining work:

1. **PFS-13 — ABI reconciliation + handle-count real query.**
   Rewrites `src/unmount_op.pdx` to the frozen path-based
   `sys_umount_shim` ABI (per sys-mount-abi.md §3); replaces
   `handle_check_query`'s hard-coded 0 stub with a real
   `VOL_OP_QUERY_HANDLE_COUNT` cap_invoke (kernel's own stub still
   returns 0, but the user-space wire is complete); issues the real
   `PMT_OP_REMOVE_ROW` cap_invoke at step 5.  Closes
   `UO_STUB_UMOUNT_ENOSYS`, `UO_STUB_ROW_REMOVE`.  Depends on PFS-01
   (this freeze), PFS-02 (`_init_caps` seed), PFS-03 (path-indexed
   slot lookup).
2. **PFS-14 — CLEAN-checkpoint pipeline closure.**  Cache flush op
   discovery + wire; superblock re-sign real body (consumes PFS-04's
   `mldsa65_verify` landed in paideia-as); closes every `UO_STUB_*`
   mask bit except LAZY_DEFERRED and ELEVATION_DENIED.  Depends on
   PFS-04 (cross-repo paideia-as), PFS-13.
3. **PFS-15 — `--force` + `--lazy` end-to-end.**
   `elevate_request_force_unmount` real body (consumes PFS-02's
   `KIND_ELEVATE_CHANNEL` broker-endpoint cap); `--lazy` DEFERRED
   completion record on last-handle-close (user-space poll loop per
   sys-mount-abi.md §7-5; kernel-side finaliser is post-PFS scope).
   Depends on PFS-02, PFS-13.

   **PFS-02 seed convention landed as design doc at paideia-os
   `design/pdxfs/init-caps-seed-convention.md` (2026-10-11)** —
   slot 4 = `KIND_PDXFS_MOUNT_TABLE` (0x1A5) with
   `R_PMT_INVOKE|R_PMT_WRITE` (0x00A) for `PMT_OP_REMOVE_ROW` at
   `src/unmount_op.pdx` step 5 + the eventual `PMT_OP_LIST` /
   `PMT_OP_READ_ROW` mount-table walk in `src/target_resolve.pdx`;
   slot 5 = `KIND_IPC_ENDPOINT` (0x005) to
   `ELEVATE_BROKER_ENDPOINT_ID = 16` with
   `R_IPC_INVOKE|R_IPC_WRITE` (0x00A) for
   `elevate_request_force_unmount` and
   `elevate_request_system_unmount`.  Cap seed from PID 1
   `_init_caps` per `design/pdxfs/init-caps-seed-convention.md` is
   the authority root; kernel enablement (grow `KIND_SEEDABLE_TABLE`
   by two entries, singleton-row mint path, broker-endpoint
   seed-time gate) is stubbed in §6 of the doc and tracked as the
   PFS-02 kernel-side follow-up.  Both LE-001 (#22) and the M3-002
   `--force` stub resolve once the follow-up lands.
4. **PFS-16 — Corpus harness + QEMU CLI integration smoke.**
   Fixture-volume mkfs → mount → write → umount → remount → readback
   matrix (10+ cases including lazy/force/elevate-required).
   Depends on PFS-10..PFS-15.
5. **LE-001 (filed under umount.pdxfs #22) — `/system` elevate gate**
   stays unreachable until PFS-15 lands.  Behaviour unchanged.

## Upstream design

`design/tooling/volume-tooling-ux.md` §5 + §9.3 and
`design/tooling/volume-lifecycle-mechanism.md` in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
