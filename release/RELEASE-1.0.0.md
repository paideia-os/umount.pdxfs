# umount.pdxfs v1.0.0 — release note + mirror-push workflow (M5-001, #15/#16)

**Repo:** github.com/paideia-os/umount.pdxfs
**Wave:** R53 volume tooling
**Version at first release:** 1.0.0
**Upstream policy:** `design/tooling/plan.md` §6.3 (paideia-os) —
package repository layout; `design/02-development-environment.md`
§1140 + §1164 (paideia-os) — hybrid Ed25519+ML-DSA-65 signing,
release-line key custody; `design/tooling/volume-tooling-ux.md` §9.3
(paideia-os) — M5-001/M5-002 scope (issues #15, #16) for this repo.

This document is both the **release note** for what v1.0.0 ships and
the operator runbook for cutting the signed release and pushing it to
the paideia-os package mirror at
`https://pkgs.paideia-os/main/umount.pdxfs/1.0.0/`. The workflow
mirrors `libpdx-volume`'s and `libpdx-audit`'s own `release/
RELEASE-1.0.0.md` / `release/RELEASE.md` templates — see either for
worked precedent, and see this file's §5 for the substantive additions
this repo's own scope (a runnable CLI, not a library) requires.

The actual `git tag v1.0.0` + `git push` is a **manual step main
performs separately from this milestone** — see §6. This document
describes exactly what that tag would contain so a future operator can
cut it without re-deriving scope from `STATUS.md` and five milestones
of design-doc flags.

---

## 1. What v1.0.0 ships

Everything landed at M1..M5 (see `CHANGELOG.md` for the itemised list,
`STATUS.md` for the per-issue checklist):

- **`TargetResolve::target_resolve`** — real `<mount-id>` resolution
  (equals the real `_mount_table[]` slot index); `<mount-point>` path
  resolution is a documented, safe dead end.
- **`HandleCheck::handle_check_refuse` / `handle_check_decide`** —
  real `IN_USE` refusal logic (`--lazy`/`--force`-aware as of M3-001),
  over a hard-stubbed always-zero handle count.
- **`UnmountOp::unmount_op`** — the real `sys_umount` syscall attempt
  (observing a stubbed `-ENOSYS` since kernel dispatch is unwired), the
  `--lazy` `DEFERRED` stub, the `--force` fail-closed `ELEVATION_STUB`
  gate, a real `pdxb_sign_superblock` call against a placeholder
  buffer feeding a real (unreachable) `SIG_KEY_LOCKED` refusal gate,
  and four stubbed teardown substeps.
- **`Elevate::elevate_request_force_unmount`** — a real, fail-closed
  `--force` elevation stub (no broker-endpoint capability exists).
- **`AuditWire`** — real `libpdx-audit @0.2` INTENT/DEFERRED/RESULT
  audit-journal wrapping around every invocation.
- **`PipeWire`** — the `libpdx-semantic-pipe` fallback wrapping every
  `PdxFsUnmountRecord@0.1` emission.
- **Five test drivers** (`tests/test_lazy_stub.pdx`,
  `tests/test_in_use.pdx`, `tests/test_lazy_deferred.pdx`,
  `tests/test_force_revoke.pdx`, `tests/test_happy_unmount.pdx`)
  exercising every real, syscall-free decision path.
- **`doc/umount.pdxfs.pdxdoc`** — the source-form user-facing
  documentation this milestone adds.

## 2. What v1.0.0 explicitly does NOT ship (deferred)

Consumers relying on this release must know these gaps are real and by
design, not oversights — see `CHANGELOG.md`'s "Known deferred
substrate" for the full write-up:

- **`dispatch_umount` unwired** — `sys_umount`'s real kernel body is
  unreachable from ring 3 regardless of this tool's own correctness.
- **`VOL_OP_QUERY_HANDLE_COUNT` + mount_id-to-cap-slot resolution** —
  `IN_USE` never fires through the real query chain.
- **`KIND_PDXFS_MOUNT_TABLE` row-remove op** — step 5 always stubs.
- **`libpdx-elevate` broker-endpoint cap** — `--force`'s elevation
  check is permanently fail-closed until one is minted.
- **`--lazy` completion callback** — a `DEFERRED` record's promised
  follow-up completion record can never fire.
- **`libpdx-semantic-pipe` schema binding** — every record stays the
  line-based fallback rendering until `libpdx-schema-registry` lands.
- **QEMU smoke matrix** — the syscall-reaching happy-path pipeline and
  every record emission need a real kernel to exercise end-to-end.
- **Dual-signed `manifest.pdxsig` + mirror push** — see §3 below.

## 3. Substrate readiness (blocking the actual signed release)

**S1 — paideia-as toolchain ≥ 0.24.0-mldsa65-sign reachable.** The
release build invokes `paideia-as build` to compile `src/*.pdx` and
`tests/*.pdx`, link against `libpdx-volume`/`libpdx-audit`/`libpdx-
elevate`, and `paideia-pq-sign::sign_release_artifact` for the
dual-signature step. `MlDsa65::sign` (the intrinsic `unmount_op.pdx`'s
own `pdxb_sign_superblock` call transitively invokes) already ships at
v0.24.0.

**S2 — `pkgs.paideia-os` mirror endpoint reachable.** Same
not-yet-standing mirror `libpdx-volume`'s and `libpdx-audit`'s own
runbooks document. Until it stands, the release is "cut but not
mirrored" — the signed `manifest.pdxsig` still lands in the GitHub
release attachment set for out-of-band consumers.

**S3 — a live ML-DSA-65 release-line seed key.** `manifest.pdxsig` is
left with the `SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN` sentinel in
every signature slot precisely because that key material is
release-line custody (hardware-backed TPM 2.0 / cloud KMS per `design/
02-development-environment.md` §1164), never repo-resident — the same
posture `libpdx-volume`'s own `pdxb_sign_superblock` documents one
level down, at the library-code level, for its own `seed_ptr`
argument.

**S4 — `doc` M2 reachable.** The compiled `.pdxdoc` at
`/pkgs/umount.pdxfs-1.0.0/doc/umount.pdxfs.pdxdoc` is produced by the
`doc compile` subcommand of the `doc` tool at doc.M2 (not landed as of
this milestone). The source form at `doc/umount.pdxfs.pdxdoc` in this
repo is the input; consumers render it verbatim until then.

**S5 — a QEMU-bootable smoke image.** Unlike `libpdx-volume` and
`libpdx-audit` (both shared libraries with no runnable executable of
their own), `umount.pdxfs` IS a runnable ELF whose own happy path
reaches a real `syscall` instruction. A genuinely end-to-end release
verification (format a volume with `mkfs.pdxfs`, mount it with
`mount.pdxfs`, unmount it with this tool, observe the real exit code
and record) needs a bootable image and a real kernel — deferred per
`tests/README.md`'s own QEMU-protocol write-up.

## 4. Cut-a-release procedure

Identical shape to `libpdx-volume`'s and `libpdx-audit`'s own runbooks
(same tooling, same release-line key custody), with this repo's own
artifact names and a link step (this tool, unlike those two libraries,
produces a linked executable, not a `.so`).

**Pre-flight.**

    git fetch origin
    git switch main
    git pull --ff-only
    git status                    # MUST be clean
    gh issue list --milestone M5 --state open --repo paideia-os/umount.pdxfs
                                  # MUST be empty

**Step 1 — Version bump + CHANGELOG close.** Already done at M5-001 —
`CHANGELOG.md`'s `## 1.0.0` entry is the one a future tag points at.

**Step 2 — Tag.** (Manual, main-performed — see §6; NOT run as part of
this milestone.)

    git tag -a v1.0.0 -m "umount.pdxfs v1.0.0 — R53 M1..M5 close"
    git push origin v1.0.0

**Step 3 — Build the compiled artifact set.**

    paideia-as build src/main.pdx src/argv.pdx src/target_resolve.pdx \
        src/handle_check.pdx src/unmount_op.pdx src/unmount_record.pdx \
        src/elevate.pdx src/audit_wire.pdx src/pipe_wire.pdx \
        -o build/umount.pdxfs.o
    paideia-as link build/umount.pdxfs.o \
        --link libpdx-volume --link libpdx-audit --link libpdx-elevate \
        -o build/umount.pdxfs
    doc compile doc/umount.pdxfs.pdxdoc -o build/umount.pdxfs.pdxdoc

**Step 4 — Recompute the manifest.**

    paideia-release fill-manifest \
        --source release/manifest.pdxsig.txt \
        --tree   . \
        --tag    v1.0.0 \
        --output build/manifest.pdxsig.filled.txt

**Step 5 — Dual-sign.**

    paideia-release sign \
        --manifest build/manifest.pdxsig.filled.txt \
        --key-ed25519  release-line-ed25519.sk \
        --key-ml-dsa65 release-line-ml-dsa-65.sk \
        --output   build/manifest.pdxsig

**Step 6 — Mirror push.**

    paideia-release mirror-push \
        --repo   https://pkgs.paideia-os/main/ \
        --pkg    umount.pdxfs \
        --version 1.0.0 \
        --files  build/umount.pdxfs \
                 build/umount.pdxfs.pdxdoc \
                 caps.decl \
                 build/manifest.pdxsig

Expected mirror layout after push:

    /pkgs/umount.pdxfs-1.0.0/
        bin/umount.pdxfs
        doc/umount.pdxfs.pdxdoc
        caps.decl
        manifest.pdxsig

**Step 7 — Update `index.pdxsig`.** Atomic as part of Step 6.

**Step 8 — GitHub release.**

    gh release create v1.0.0 \
        --title "umount.pdxfs v1.0.0" \
        --notes-file CHANGELOG.md \
        build/manifest.pdxsig \
        build/umount.pdxfs \
        build/umount.pdxfs.pdxdoc \
        caps.decl

---

## 5. What this repo's scope adds over the library template

`libpdx-volume`'s and `libpdx-audit`'s own release runbooks are the
template §4 above follows almost verbatim, with two substantive
additions specific to a runnable CLI tool rather than a shared library:

- **A link step** (Step 3 above) — this repo's own `caps.decl` declares
  three satellite-library dependencies (`libpdx-volume`, `libpdx-
  audit`, `libpdx-elevate`) that must actually be resolved at link
  time, unlike a leaf library with no dependencies of its own.
- **§3 S5** — the QEMU-bootable-image substrate requirement, since this
  tool's own happy path (unlike anything either dependency library
  exposes) reaches a real `syscall` instruction that only a genuine
  kernel can service.

## 6. Consumers who can rely on this release today

A `shell` or script invoking `umount.pdxfs <mount-id>` after `mount.
pdxfs` returned that `mount_id` can rely on:

- A real `sys_umount` attempt being issued (though its kernel-side
  dispatch is currently unwired — see `CHANGELOG.md`).
- `PdxFsUnmountRecord@0.1`'s `result_code` field accurately reflecting
  which of `OK`/`IN_USE`/`KERNEL_ERROR`/`MOUNT_NOT_FOUND`/`DEFERRED`/
  `ELEVATION_STUB`/`SIG_KEY_LOCKED` applies, and `stub_mask` accurately
  reflecting which teardown substeps ran for real.
- `--dry-run` never mutating anything.

A consumer must NOT rely on:

- `<mount-point>` path resolution ever succeeding.
- `IN_USE` ever actually refusing (the handle-count query is a hard
  stub).
- `--lazy`'s promised completion record ever arriving.
- `--force` ever actually bypassing a refusal (the elevation check is
  permanently fail-closed at this release).
- `SIG_KEY_LOCKED` being reachable at all.

## 7. Verification (consumer side)

    pkg install umount.pdxfs --verify-only     # dry run, no install
    pkg keys show paideia-release-line           # inspect the signer

AND-semantics per the hybrid scheme: both Ed25519 and ML-DSA-65 MUST
verify; either failure REJECTS the package. Not runnable until the
placeholder signature block in `manifest.pdxsig` is replaced by a real
dual-sign pass per §3/§4 above.

---

## 8. What lands at M5-001/M5-002 (this milestone, #15/#16)

Repo-side, M5-001 lands the source form of the release:

- `CHANGELOG.md` — v1.0.0 entry summarising M1..M5.
- `doc/umount.pdxfs.pdxdoc` — source-form `.pdxdoc` for `doc
  umount.pdxfs`.
- `release/manifest.pdxsig.txt` — release manifest source form, every
  hash and every signature slot a documented placeholder.
- `release/RELEASE-1.0.0.md` — this document (also covers M5-002's
  mirror-push documentation, per #16).
- `STATUS.md` — M1..M5 marked landed.

**Not performed at this milestone:** the git tag itself (main's manual
step, once this landing is reviewed), the actual `paideia-as build` +
link compile pass, the dual-sign pass (no live seed key in this repo —
§3 S3), and the mirror push (mirror endpoint does not exist yet — §3
S2, tracked as #16's own not-yet-executable scope).
