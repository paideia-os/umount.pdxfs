# umount.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M1 (design + skeleton) — **landed**
**Version:** unreleased (pre-1.0.0)

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

### M2 — Core implementation (pending)

- [ ] **M2-001** — mount-point → mount_id resolution via
      `libpdx-volume.mount_table_snapshot`.
- [ ] **M2-002** — `KIND_VOLUME.VOL_OP_QUERY_HANDLE_COUNT` wiring +
      `IN_USE` refusal (exit 5).
- [ ] **M2-003** — non-force happy path: cache flush + txn drain +
      `CLEAN` checkpoint + superblock resign+rewrite + row remove.

### M3 — `--lazy` + `--force` + audit-first + semantic-pipe (pending)

- [ ] **M3-001** — `--lazy` path: `PENDING_UNMOUNT` flag + `DEFERRED`
      completion record on last handle close.
- [ ] **M3-002** — `--force` path: `libpdx-elevate` + handle-revoke +
      `revoked_handles` list in record. `src/elevate.pdx`'s module
      header names this as its future live-code landing point.
- [ ] **M3-003** — semantic-pipe: `PdxFsUnmountRecord@0.1` schema bind
      + emit (`INTENT` + `RESULT` + `DEFERRED`).
- [ ] **M3-004** — `SIG_KEY_LOCKED` refusal path (superblock cannot be
      re-signed → refuse without `--force`).

### M4 — Tests + smoke (pending)

- [ ] **M4-001** — happy-path smoke: unmount `/mnt` with no open
      handles → volume clean.
- [ ] **M4-002** — `IN_USE` refusal smoke: open handle blocks umount
      without `--force` / `--lazy`.
- [ ] **M4-003** — `--lazy` correctness: umount deferred until last
      handle closes; `DEFERRED` record fires.
- [ ] **M4-004** — `--force` correctness: revoked handles named in
      record; subsequent I/O returns `EIO`.

### M5 — Signed release (pending)

- [ ] **M5-001** — dual-signed `manifest.pdxsig` + `CHANGELOG-1.0` +
      `.pdxdoc` for `doc umount.pdxfs`.
- [ ] **M5-002** — mirror push to `pkgs.paideia-os`.

## Next milestone

M2 opens once `umount.pdxfs.M1` closes and `libpdx-volume.M2`'s
`mount_table_snapshot` (M2-001 in that repo) lands with a real body —
`umount.pdxfs.M2-001`'s mount-point resolution links that function
directly. `libpdx-volume.M1` has landed (see
[`libpdx-volume`](https://github.com/paideia-os/libpdx-volume)); confirm
`libpdx-volume.M2` timing before opening `umount.pdxfs.M2-001`.

## Upstream design

`design/tooling/volume-tooling-ux.md` §5 + §9.3 and
`design/tooling/volume-lifecycle-mechanism.md` in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
