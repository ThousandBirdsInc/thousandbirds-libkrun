#!/bin/sh
set -eu

features="${KRUN_OSMODE_FEATURES:-blk net}"
target_dir="${CARGO_TARGET_DIR:-target/linux-container}"
export CARGO_TARGET_DIR="${target_dir}"

is_single_token() {
    case "$1" in
        ''|*[[:space:]]*)
            return 1
            ;;
    esac
    return 0
}

require_single_token() {
    name=$1
    value=$2
    if ! is_single_token "$value"; then
        echo "$name must be a non-empty single kernel command-line token" >&2
        exit 2
    fi
}

is_positive_integer() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    if [ "$1" -eq 0 ]; then
        return 1
    fi
    return 0
}

require_positive_integer() {
    name=$1
    value=$2
    if ! is_positive_integer "$value"; then
        echo "$name must be a positive integer" >&2
        exit 2
    fi
}

is_kernel_format() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    if [ "$1" -gt 5 ]; then
        return 1
    fi
    return 0
}

is_non_empty_file() {
    [ -n "$1" ] && [ -f "$1" ]
}

is_non_empty_socket() {
    [ -n "$1" ] && [ -S "$1" ]
}

require_kernel_format() {
    name=$1
    value=$2
    if ! is_kernel_format "$value"; then
        echo "$name must be an integer from 0 through 5" >&2
        exit 2
    fi
}

require_file() {
    name=$1
    value=$2
    if ! is_non_empty_file "$value"; then
        echo "$name does not exist or is not a file: $value" >&2
        exit 2
    fi
}

require_non_empty() {
    name=$1
    value=$2
    if [ -z "$value" ]; then
        echo "$name must be non-empty" >&2
        exit 2
    fi
}

require_socket() {
    name=$1
    value=$2
    if ! is_non_empty_socket "$value"; then
        echo "$name does not exist or is not a unix socket: $value" >&2
        exit 2
    fi
}

require_parent_dir() {
    name=$1
    value=$2
    if [ -z "$value" ]; then
        echo "$name must be non-empty" >&2
        exit 2
    fi
    parent=$(dirname "$value")
    if [ ! -d "$parent" ]; then
        echo "$name parent directory does not exist: $parent" >&2
        exit 2
    fi
}

if [ "${KRUN_OSMODE_LINUX_VALIDATE_SELFTEST:-0}" = "1" ]; then
    require_single_token TEST_TOKEN ttyS0
    if is_single_token "ttyS0 quiet"; then
        echo "is_single_token accepted whitespace" >&2
        exit 1
    fi
    require_positive_integer TEST_TIMEOUT 15
    if is_positive_integer 0 || is_positive_integer bad; then
        echo "is_positive_integer accepted invalid input" >&2
        exit 1
    fi
    require_kernel_format TEST_KERNEL_FORMAT 5
    if is_kernel_format 6 || is_kernel_format bad; then
        echo "is_kernel_format accepted invalid input" >&2
        exit 1
    fi
    require_file TEST_FILE "$0"
    if is_non_empty_file "" || is_non_empty_file "$0.missing"; then
        echo "is_non_empty_file accepted invalid input" >&2
        exit 1
    fi
    if is_non_empty_socket "" || is_non_empty_socket "$0"; then
        echo "is_non_empty_socket accepted invalid input" >&2
        exit 1
    fi
    require_non_empty TEST_EXPECT_MARKER "KRUN_OSMODE: network=up"
    require_single_token TEST_EXPECT_CONSOLE ttyS0
    require_parent_dir TEST_SMOKE_JSON "$0.json"
    exit 0
fi

if [ ! -f examples/os_mode.c ]; then
    echo "os_mode_linux_validate.sh must run from the libkrun repository root." >&2
    echo "For Docker, mount the repo with: -v \"\$PWD:/workspace/libkrun\"" >&2
    exit 1
fi

host_checks="${KRUN_OSMODE_HOST_CHECKS:-ci/os_mode_host_checks.sh}"
if [ ! -x "${host_checks}" ] && [ -x /usr/local/bin/os_mode_host_checks.sh ]; then
    host_checks=/usr/local/bin/os_mode_host_checks.sh
fi

echo "==> host-independent OS-mode checks"
"${host_checks}"

echo "==> cargo unit tests: ${features}"
KRUN_INIT_BINARY_PATH="${KRUN_INIT_BINARY_PATH:-/bin/echo}" \
    cargo test -p libkrun --features "${features}" --lib

echo "==> C API compile check"
cc -fsyntax-only -Iinclude examples/os_mode.c

echo "==> release build"
cargo build --release --features "${features}"

echo "==> example build"
cc -o /tmp/os_mode examples/os_mode.c -O2 -g -Iinclude \
    -L"${target_dir}/release" \
    -Wl,-rpath,"${PWD}/${target_dir}/release" \
    -lkrun

if [ "${RUN_KVM_SMOKE:-0}" != "1" ]; then
    echo "==> skipping KVM smoke; set RUN_KVM_SMOKE=1 and pass --device /dev/kvm to Docker"
    exit 0
fi

if [ ! -c /dev/kvm ]; then
    echo "RUN_KVM_SMOKE=1 requires /dev/kvm inside the container" >&2
    exit 1
fi

: "${KRUN_OSMODE_KERNEL:?set KRUN_OSMODE_KERNEL to a guest kernel path inside the container}"
: "${KRUN_OSMODE_ROOT:?set KRUN_OSMODE_ROOT to a raw root disk path inside the container}"

kernel_format="${KRUN_OSMODE_KERNEL_FORMAT:-1}"
root_device="${KRUN_OSMODE_ROOT_DEVICE:-/dev/vda}"
root_fstype="${KRUN_OSMODE_ROOT_FSTYPE:-ext4}"
console="${KRUN_OSMODE_CONSOLE:-ttyS0}"
expect_console="${KRUN_OSMODE_EXPECT_CONSOLE:-${console}}"
timeout="${KRUN_OSMODE_TIMEOUT:-15}"
root_options="${KRUN_OSMODE_ROOT_OPTIONS:-}"
expect_root="${KRUN_OSMODE_EXPECT_ROOT:-${root_device}}"
passt_socket="${KRUN_OSMODE_PASST_SOCKET:-}"
expect_marker="${KRUN_OSMODE_EXPECT_MARKER:-}"
smoke_json="${KRUN_OSMODE_SMOKE_JSON:-}"

require_file KRUN_OSMODE_KERNEL "${KRUN_OSMODE_KERNEL}"
require_file KRUN_OSMODE_ROOT "${KRUN_OSMODE_ROOT}"
require_kernel_format KRUN_OSMODE_KERNEL_FORMAT "${kernel_format}"
require_single_token KRUN_OSMODE_ROOT_DEVICE "${root_device}"
require_single_token KRUN_OSMODE_ROOT_FSTYPE "${root_fstype}"
require_single_token KRUN_OSMODE_CONSOLE "${console}"
require_single_token KRUN_OSMODE_EXPECT_CONSOLE "${expect_console}"
require_positive_integer KRUN_OSMODE_TIMEOUT "${timeout}"
require_single_token KRUN_OSMODE_EXPECT_ROOT "${expect_root}"
if [ -n "${root_options}" ]; then
    require_single_token KRUN_OSMODE_ROOT_OPTIONS "${root_options}"
fi
if [ -n "${passt_socket}" ]; then
    require_socket KRUN_OSMODE_PASST_SOCKET "${passt_socket}"
fi
if [ -n "${expect_marker}" ]; then
    require_non_empty KRUN_OSMODE_EXPECT_MARKER "${expect_marker}"
fi
if [ -n "${smoke_json}" ]; then
    require_parent_dir KRUN_OSMODE_SMOKE_JSON "${smoke_json}"
fi

set -- /tmp/os_mode \
    --kernel "${KRUN_OSMODE_KERNEL}" \
    --kernel-format "${kernel_format}" \
    --root-disk "${KRUN_OSMODE_ROOT}" \
    --root-device "${root_device}" \
    --root-fstype "${root_fstype}" \
    --console "${console}"

if [ -n "${KRUN_OSMODE_INITRAMFS:-}" ]; then
    require_file KRUN_OSMODE_INITRAMFS "${KRUN_OSMODE_INITRAMFS}"
    set -- "$@" --initramfs "${KRUN_OSMODE_INITRAMFS}"
fi

if [ -n "${root_options}" ]; then
    set -- "$@" --root-options "${root_options}"
fi

if [ -n "${passt_socket}" ]; then
    set -- "$@" --passt-socket "${passt_socket}"
fi

if [ -n "${KRUN_OSMODE_KERNEL_CMDLINE:-}" ]; then
    set -- "$@" --kernel-cmdline "${KRUN_OSMODE_KERNEL_CMDLINE}"
fi

echo "==> KVM smoke"
if [ -n "${expect_marker}" ] && [ -n "${smoke_json}" ]; then
    python3 examples/os_mode_smoke.py \
        --timeout "${timeout}" \
        --expect-root "${expect_root}" \
        --expect-console "${expect_console}" \
        --expect-marker "${expect_marker}" \
        --output "${smoke_json}" \
        -- "$@"
elif [ -n "${expect_marker}" ]; then
    python3 examples/os_mode_smoke.py \
        --timeout "${timeout}" \
        --expect-root "${expect_root}" \
        --expect-console "${expect_console}" \
        --expect-marker "${expect_marker}" \
        -- "$@"
elif [ -n "${smoke_json}" ]; then
    python3 examples/os_mode_smoke.py \
        --timeout "${timeout}" \
        --expect-root "${expect_root}" \
        --expect-console "${expect_console}" \
        --output "${smoke_json}" \
        -- "$@"
else
    python3 examples/os_mode_smoke.py \
        --timeout "${timeout}" \
        --expect-root "${expect_root}" \
        --expect-console "${expect_console}" \
        -- "$@"
fi
