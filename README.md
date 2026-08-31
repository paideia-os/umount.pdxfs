# umount.pdxfs

paideia-os PdxFS volume unmount tool — resolves a mount-id or
mount-point to a mount-table row, drives the WAL through a clean
checkpoint, and detaches the volume (`sys_umount`).

## Purpose

`umount.pdxfs` is the reversal of the third-of-three actions that bring
a blank disk (or image file) online for PdxFS v1: **format**
(`mkfs.pdxfs`), then **mount** (`mount.pdxfs`), with `umount.pdxfs` as
the teardown. It is invoked as:

```
umount.pdxfs [--lazy] [--force] [--verbose] [--dry-run] <mount-id | mount-point>
```

`<mount-id | mount-point>` is either the u64 id from a prior
`PdxFsMountRecord@0.1`'s `mount_id` field, or a VFS path the tool
resolves to a mount_id by scanning the mount table. See
[`design/architecture.md`](design/architecture.md) for the full
argv write-up and `design/tooling/volume-tooling-ux.md` §5 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
upstream CLI spec this tool implements.

## Status

**M1 landed** (scaffold + caps.decl, argv surface, first runnable
`--dry-run`). See [`STATUS.md`](STATUS.md) for the per-issue checklist
and `design/tooling/volume-tooling-ux.md` §9.3 in paideia-os for the
full M1..M5 milestone breakdown (16 issues).

Try it (once built and linked into a runnable image):

```
umount.pdxfs --dry-run --lazy /mnt/foo
```

prints:

```
PdxFsUnmountRecord@0.1 { target: /mnt/foo, flags: 1, result_code: DRY_RUN }
```

and exits 0 without unmounting anything. Any invocation without
`--dry-run` currently prints `umount.pdxfs: not yet implemented` to
stderr and exits 1 — the real teardown path (mount-table resolution,
handle-count query, cache flush + txn drain + checkpoint, `--lazy` /
`--force` handling) lands at M2/M3.

## Depends on

- **`libpdx-volume`** (`paideia-os/libpdx-volume`) — M1 landed. Will
  supply `mount_table_snapshot` (mount-point → mount_id resolution)
  this tool's M2 links against. Not yet linked by any M1 code in this
  repo — see `design/architecture.md` §2 for the dependency-wiring
  plan.
- **R53-PREP-001** — `KIND_PDXFS_MOUNT_TABLE` (0x1A5), landed.
- **R53-PREP-002** — the `UEJ_KIND_VOL_UNMOUNT` audit-journal
  registration this tool's M3 audit path needs.
- **paideia-as ≥ 0.21.0** (build toolchain).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M1 | Scaffold, caps.decl, argv surface, first runnable `--dry-run` | **Landed** |
| M2 | Mount-point resolution, handle-count query, non-force happy path | Pending |
| M3 | `--lazy` + `--force` + audit-first + semantic-pipe | Pending |
| M4 | Tests + smoke | Pending |
| M5 | Signed release | Pending |

## License

MIT — see [`LICENSE`](LICENSE).
