#!/bin/sh
set -eu

usage() {
    cat >&2 <<EOF
Usage: $0 WORKDIR [SIZE_MB]

Creates a temporary raw base image, creates an APFS clone with
os_mode_apfs_clone.sh, writes to the clone, verifies the base checksum is
unchanged, deletes the clone, and prints timing/allocation data.
EOF
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 2
fi

workdir=$1
size_mb=${2:-64}

if [ -z "$workdir" ]; then
    echo "Work directory must be non-empty." >&2
    exit 2
fi
case "$size_mb" in
    ''|*[!0-9]*)
        echo "SIZE_MB must be a positive integer." >&2
        exit 2
        ;;
esac
if [ "$size_mb" -eq 0 ]; then
    echo "SIZE_MB must be a positive integer." >&2
    exit 2
fi

base=$workdir/base.raw
clone=$workdir/clone.raw

mkdir -p "$workdir"
rm -f "$base" "$clone"

mkfile "${size_mb}m" "$base"
chmod a-w "$base"

base_before=$(shasum -a 256 "$base" | awk '{print $1}')
full_copy=$workdir/full-copy.raw
rm -f "$full_copy"

now_ms() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(time.monotonic_ns() // 1000000)'
    else
        echo "$(($(date +%s) * 1000))"
    fi
}

full_start=$(now_ms)
cp "$base" "$full_copy"
full_end=$(now_ms)
full_elapsed_ms=$((full_end - full_start))
full_allocated_kib=$(du -k "$full_copy" | awk '{print $1}')
rm -f "$full_copy"

helper_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
clone_output=$("$helper_dir/os_mode_apfs_clone.sh" "$base" "$clone")
echo "$clone_output"

clone_allocated_before=$(du -k "$clone" | awk '{print $1}')
printf 'KRUN_OSMODE_APFS: writing clone\n'
printf 'clone-write-test' | dd of="$clone" bs=1 seek=4096 conv=notrunc 2>/dev/null
clone_allocated_after=$(du -k "$clone" | awk '{print $1}')
base_after=$(shasum -a 256 "$base" | awk '{print $1}')

if [ "$base_before" != "$base_after" ]; then
    echo "Base image checksum changed after clone write" >&2
    exit 1
fi

rm -f "$clone"
if [ -e "$clone" ]; then
    echo "Clone cleanup failed" >&2
    exit 1
fi

echo "full_copy_elapsed_ms=$full_elapsed_ms"
echo "full_copy_allocated_kib=$full_allocated_kib"
echo "clone_allocated_before_kib=$clone_allocated_before"
echo "clone_allocated_after_write_kib=$clone_allocated_after"
echo "base_sha256=$base_after"
echo "cleanup=ok"
