#!/usr/bin/env bash
# Per-repo build script. Runs paideia-as build over every .pdx source, then
# links the resulting objects into build-out/umount.pdxfs.elf via `ld`
# (paideia-os#1976/#1977 satellite-tool embedding pipeline).
#
# Resolves paideia-as via (in order):
#   1. $PAIDEIA_AS env var
#   2. paideia-os checkout sibling to this repo: ../paideia-os/tools/paideia-as/target/release/paideia-as
#   3. $HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as
#   4. paideia-as on $PATH (must be >= 0.21.0)
#
# Requires paideia-as >= 0.21.0. The 0.9.0 shipped in $PATH by default does not
# accept the syntax used in this repo.
#
# Usage:
#   tools/build.sh [--extra-obj-dir DIR]... [--extra-archive PATH]...
#
# --extra-obj-dir DIR may be repeated. Every *.o file found directly inside
# each DIR is added to the `ld` link line alongside this repo's own
# src/*.pdx objects (e.g. a dependency's build-out directory). A DIR that
# does not exist, or that contains no .o files, contributes nothing and is
# NOT an error.
#
# --extra-archive PATH may be repeated. Each PATH is a static archive
# (`.a`) appended to the final `ld` link line AFTER the --extra-obj-dir
# objects (paideia-os#2226, satellite-runtime-shim design §4.1/§5).
# Archives on the link line are pulled in AS-NEEDED (unlike loose
# objects, which link unconditionally); `--gc-sections` then prunes the
# unused Rust symbols from the Phase A/B satellite-runtime + audit-
# satellite archives so they never reach the output ELF. Standard
# invocation:
#
#   bash tools/build.sh \
#     --extra-obj-dir ../libpdx-volume/build-out \
#     --extra-archive .../libpaideia_satellite_runtime.a \
#     --extra-archive .../libpdx-audit-satellite.a
#
# Linking phase: once every src/*.pdx compiles cleanly, this repo's own
# object files (build-out/*.o from src/*.pdx -- never the build-out/tests-
# *.o unit-test scaffolding) plus any --extra-obj-dir objects and any
# --extra-archive archives are linked via `ld -T link.ld --gc-sections`
# into build-out/umount.pdxfs.elf, then objcopy'd to
# build-out/umount.pdxfs.bin.

set -euo pipefail

EXTRA_OBJECTS=()
EXTRA_ARCHIVES=()
OWN_OBJECTS=()
EXTRA_OBJ_DIRS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --extra-obj-dir)
            if [ "$#" -lt 2 ]; then
                echo "[build] FAIL: --extra-obj-dir requires an argument" >&2
                exit 2
            fi
            EXTRA_OBJ_DIRS+=("$2")
            shift 2
            ;;
        --extra-archive)
            if [ "$#" -lt 2 ]; then
                echo "[build] FAIL: --extra-archive requires an argument" >&2
                exit 2
            fi
            EXTRA_ARCHIVES+=("$2")
            shift 2
            ;;
        *)
            echo "[build] FAIL: unrecognized argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$(dirname "$0")/.."

MIN_VERSION="0.21.0"

resolve_paideia_as() {
    if [ -n "${PAIDEIA_AS:-}" ] && [ -x "$PAIDEIA_AS" ]; then
        echo "$PAIDEIA_AS"; return
    fi
    for cand in \
        "../paideia-os/tools/paideia-as/target/release/paideia-as" \
        "$HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as"
    do
        if [ -x "$cand" ]; then
            echo "$cand"; return
        fi
    done
    if command -v paideia-as >/dev/null 2>&1; then
        command -v paideia-as; return
    fi
    return 1
}

version_ge() {
    # $1 = have, $2 = want ; returns 0 if have >= want
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

PA="$(resolve_paideia_as || true)"
if [ -z "$PA" ]; then
    echo "[build] FAIL: paideia-as not found. Set PAIDEIA_AS or clone paideia-os as a sibling." >&2
    exit 2
fi
VER="$("$PA" --version | awk '{print $2}')"
if ! version_ge "$VER" "$MIN_VERSION"; then
    echo "[build] FAIL: paideia-as $VER is too old, need >= $MIN_VERSION (found $PA)" >&2
    exit 2
fi
echo "[build] paideia-as $VER at $PA"

BUILD_DIR="build-out"
mkdir -p "$BUILD_DIR"

FAIL=0
COUNT=0
for pdx in src/*.pdx; do
    [ -f "$pdx" ] || continue
    COUNT=$((COUNT + 1))
    obj="$BUILD_DIR/$(basename "$pdx" .pdx).o"
    if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
        FAIL=$((FAIL + 1))
    else
        OWN_OBJECTS+=("$obj")
    fi
done

if [ -d tests ]; then
    for pdx in tests/*.pdx; do
        [ -f "$pdx" ] || continue
        COUNT=$((COUNT + 1))
        obj="$BUILD_DIR/tests-$(basename "$pdx" .pdx).o"
        if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
            FAIL=$((FAIL + 1))
        fi
    done
fi

echo "[build] $COUNT source(s), $FAIL failure(s)"
[ "$FAIL" -eq 0 ] || exit 1
echo "[build] OK"

# ---- Gather extra objects from --extra-obj-dir directories. ----------------
shopt -s nullglob
for dir in "${EXTRA_OBJ_DIRS[@]}"; do
    for obj in "$dir"/*.o; do
        [ -f "$obj" ] || continue
        EXTRA_OBJECTS+=("$obj")
    done
done
shopt -u nullglob

# ---- Link phase: OWN_OBJECTS + EXTRA_OBJECTS + EXTRA_ARCHIVES ->
# ---- build-out/umount.pdxfs.elf.
if [ "$FAIL" -eq 0 ] && [ "${#OWN_OBJECTS[@]}" -gt 0 ]; then
    echo "[link] ld -T link.ld -> $BUILD_DIR/umount.pdxfs.elf"
    ld -nostdlib --warn-common --fatal-warnings --gc-sections \
        -T link.ld \
        -o "$BUILD_DIR/umount.pdxfs.elf" \
        "${OWN_OBJECTS[@]}" "${EXTRA_OBJECTS[@]}" "${EXTRA_ARCHIVES[@]}"
    echo "[link] OK -> $BUILD_DIR/umount.pdxfs.elf"

    objcopy -O binary "$BUILD_DIR/umount.pdxfs.elf" "$BUILD_DIR/umount.pdxfs.bin"
    echo "[link] OK -> $BUILD_DIR/umount.pdxfs.bin"
fi
