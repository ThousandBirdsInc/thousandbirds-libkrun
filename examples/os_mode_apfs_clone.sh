#!/bin/sh
set -eu

usage() {
    cat >&2 <<EOF
Usage: $0 BASE_IMAGE CLONE_IMAGE

Creates CLONE_IMAGE as an APFS CoW clone of BASE_IMAGE using macOS cp -c.
The source and destination must be on the same APFS volume for metadata-cheap
cloning. Set ALLOW_FULL_COPY=1 to fall back to a full copy if clone creation is
not supported.
EOF
}

if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

base=$1
clone=$2

if [ -z "$base" ]; then
    echo "Base image path must be non-empty." >&2
    exit 2
fi
if [ -z "$clone" ]; then
    echo "Clone image path must be non-empty." >&2
    exit 2
fi

clone_dir=$(dirname "$clone")

now_ms() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(time.monotonic_ns() // 1000000)'
    else
        echo "$(($(date +%s) * 1000))"
    fi
}

if [ ! -f "$base" ]; then
    echo "Base image does not exist: $base" >&2
    exit 1
fi

mkdir -p "$clone_dir"

if [ -e "$clone" ] || [ -L "$clone" ]; then
    echo "Clone destination already exists: $clone" >&2
    echo "Refusing to overwrite an existing VM root disk." >&2
    exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then
    fs_type() {
        path=$1
        mount_point=$(df -P "$path" 2>/dev/null | awk 'NR == 2 {print $6}')
        if [ -z "$mount_point" ]; then
            echo unknown
            return
        fi
        mount | awk -v mp="$mount_point" '
            index($0, " on " mp " (") {
                sub(/^.* \(/, "")
                sub(/,.*/, "")
                sub(/\)$/, "")
                print
                exit
            }'
    }

    base_fs=$(fs_type "$base")
    clone_fs=$(fs_type "$clone_dir")
    base_dev=$(stat -f %d "$base" 2>/dev/null || echo unknown)
    clone_dev=$(stat -f %d "$clone_dir" 2>/dev/null || echo unknown)

    if [ "$base_fs" != "apfs" ] || [ "$clone_fs" != "apfs" ]; then
        if [ "${ALLOW_FULL_COPY:-0}" != "1" ]; then
            echo "APFS clone preflight failed." >&2
            echo "base filesystem=$base_fs clone directory filesystem=$clone_fs" >&2
            echo "Set ALLOW_FULL_COPY=1 to create a slower full copy fallback." >&2
            exit 1
        fi
    elif [ "$base_dev" != "$clone_dev" ]; then
        if [ "${ALLOW_FULL_COPY:-0}" != "1" ]; then
            echo "APFS clone preflight failed: source and destination are not on the same volume." >&2
            echo "base device=$base_dev clone directory device=$clone_dev" >&2
            echo "Set ALLOW_FULL_COPY=1 to create a slower full copy fallback." >&2
            exit 1
        fi
    fi
fi

clone_name=$(basename "$clone")
tmp_dir=$(mktemp -d "$clone_dir/.${clone_name}.tmp.XXXXXX")
tmp_clone=$tmp_dir/root.raw
cleanup_tmp() {
    rm -rf "$tmp_dir"
}
trap cleanup_tmp EXIT HUP INT TERM

start_ms=$(now_ms)
if cp -c "$base" "$tmp_clone" 2>/dev/null; then
    mode=clone
else
    if [ "${ALLOW_FULL_COPY:-0}" != "1" ]; then
        echo "APFS clone failed. Ensure both paths are on the same APFS volume." >&2
        echo "Set ALLOW_FULL_COPY=1 to create a slower full copy fallback." >&2
        exit 1
    fi
    cp "$base" "$tmp_clone"
    mode=full-copy
fi

chmod u+w "$tmp_clone"
if ! ln "$tmp_clone" "$clone" 2>/dev/null; then
    echo "Failed to publish clone at $clone." >&2
    echo "The destination may have been created by another launcher." >&2
    exit 1
fi
rm -rf "$tmp_dir"
trap - EXIT HUP INT TERM
end_ms=$(now_ms)

elapsed_ms=$((end_ms - start_ms))
allocated=$(du -k "$clone" | awk '{print $1}')

echo "mode=$mode"
echo "elapsed_ms=$elapsed_ms"
echo "allocated_kib=$allocated"
echo "clone=$clone"
