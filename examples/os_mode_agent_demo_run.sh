#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workdir=${AGENT_WORKDIR:-"$repo_root/os_mode_artifacts/debian-agent-demo"}
cache_dir=${KRUN_OSMODE_CACHE_DIR:-"$repo_root/os_mode_artifacts/debian-recording-cache"}
react_app=${KRUN_AGENT_REACT_APP:-"$repo_root/examples/agent_react_app"}
root=${KRUN_AGENT_ROOT:-"$workdir/agent-vm-root.raw"}

base_bundle=${BASE_BUNDLE:-}
if [ -n "$base_bundle" ] && { [ ! -f "$base_bundle/kernel" ] || [ ! -f "$base_bundle/initramfs" ]; }; then
    echo "Ignoring invalid BASE_BUNDLE: $base_bundle" >&2
    base_bundle=
fi
if [ -z "$base_bundle" ]; then
    base_bundle=$(find "$cache_dir" -type d -name libkrun-os-bundle -print -quit)
fi

if [ -z "$base_bundle" ] || [ ! -f "$base_bundle/kernel" ] || [ ! -f "$base_bundle/initramfs" ]; then
    echo "Could not find OS-mode kernel/initramfs bundle under: $cache_dir" >&2
    echo "Set BASE_BUNDLE=/path/to/libkrun-os-bundle and retry." >&2
    exit 1
fi

if [ ! -f "$workdir/root.raw" ]; then
    echo "Missing base root disk: $workdir/root.raw" >&2
    echo "Build it with examples/os_mode_agent_demo.md first." >&2
    exit 1
fi

if [ ! -f "$root" ]; then
    "$repo_root/examples/os_mode_apfs_clone.sh" "$workdir/root.raw" "$root"
fi

if [ ! -d "$react_app" ]; then
    echo "Missing React app directory: $react_app" >&2
    exit 1
fi

cat <<EOF
Booting Claude Code agent demo:
  bundle: $base_bundle
  root:   $root
  app:    $react_app

After the guest reaches the # prompt, run:
  agent-demo-enter
  su - agent
  cd /workspace/react-app
  claude auth login --console
  claude

EOF

exec "$repo_root/examples/os_mode" \
    --kernel "$base_bundle/kernel" \
    --kernel-format 2 \
    --initramfs "$base_bundle/initramfs" \
    --root-disk "$root" \
    --root-device /dev/vda \
    --root-fstype ext4 \
    --guest-init /sbin/init \
    --console ttyAMA0 \
    --kernel-cmdline 'rw systemd.unit=multi-user.target' \
    --virtiofs "react-app=$react_app"
