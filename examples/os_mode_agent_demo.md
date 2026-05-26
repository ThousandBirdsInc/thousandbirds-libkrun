# Claude Code Agent Demo

This demo profile runs a Debian OS-mode guest that is useful for interactive AI
agent work:

- Debian `bookworm` systemd userspace.
- Node.js, npm, Git, ripgrep, and Chromium.
- Claude Code installed for a non-root `agent` user.
- A validation serial-control shell so the host terminal can send commands into
  the running guest.
- A host React workspace mounted into the guest with non-root virtio-fs.

Claude Code currently supports Debian/Ubuntu-class Linux hosts with Node.js 18+
and can be installed with `npm install -g @anthropic-ai/claude-code`. The image
installs it as the `agent` user, not with `sudo npm install -g`.

## Build The Source Image

```sh
docker build \
  --platform linux/arm64 \
  -f ci/os_mode_debian_agent.Containerfile \
  -t libkrun-osmode-debian-agent:bookworm-arm64 \
  .
```

## Build The OS Root Disk

Use the known-good OS-mode kernel and initramfs from an extracted Debian bundle
cache, or substitute equivalent aarch64 virtio-mmio artifacts:

```sh
export AGENT_WORKDIR="$PWD/os_mode_artifacts/debian-agent-demo"
export BASE_BUNDLE="$PWD/os_mode_artifacts/debian-recording-cache/libkrun-osmode-debian-systemd-bundle-d711a9d1ad3a73b1/libkrun-os-bundle"

examples/os_mode_build_container_rootfs.py \
  --image libkrun-osmode-debian-agent:bookworm-arm64 \
  --output-dir "$AGENT_WORKDIR" \
  --runtime docker \
  --platform linux/arm64 \
  --size-mb 4096 \
  --require-apfs-output \
  --init-mode systemd \
  --systemd-serial-control-shell \
  --no-smoke-poweroff-after-ready \
  --smoke-timeout 180 \
  --kernel "$BASE_BUNDLE/kernel" \
  --kernel-format 2 \
  --initramfs "$BASE_BUNDLE/initramfs"
```

The `--systemd-serial-control-shell` flag is intentionally for demos and
validation. It gives the host terminal a root shell on `ttyAMA0` after systemd
prints the OS-mode readiness markers.

## Boot With The React Workspace Mounted

The shortest path is the wrapper, which finds the extracted kernel/initramfs
bundle and reuses or creates the writable APFS clone:

```sh
examples/os_mode_agent_demo_run.sh
```

To use a different writable root clone:

```sh
KRUN_AGENT_ROOT="$AGENT_WORKDIR/agent-vm-root-$(date +%Y%m%d-%H%M%S).raw" \
  examples/os_mode_agent_demo_run.sh
```

The equivalent manual commands are:

```sh
examples/os_mode_apfs_clone.sh \
  "$AGENT_WORKDIR/root.raw" \
  "$AGENT_WORKDIR/agent-vm-root.raw"

examples/os_mode \
  --kernel "$BASE_BUNDLE/kernel" \
  --kernel-format 2 \
  --initramfs "$BASE_BUNDLE/initramfs" \
  --root-disk "$AGENT_WORKDIR/agent-vm-root.raw" \
  --root-device /dev/vda \
  --root-fstype ext4 \
  --guest-init /sbin/init \
  --console ttyAMA0 \
  --kernel-cmdline 'rw systemd.unit=multi-user.target' \
  --virtiofs react-app="$PWD/examples/agent_react_app"
```

When the serial-control shell appears, run:

```sh
agent-demo-enter
su - agent
cd /workspace/react-app
chromium --headless --no-sandbox --disable-gpu --dump-dom file://$PWD/index.html
claude auth login --console
claude
```

Claude Code will print an authentication URL or code. Open that URL on the host
and complete login with your own Claude or Anthropic Console credentials. The
guest stores credentials under `/home/agent`, which lives in the writable APFS
clone. Keep that clone if you want the login to persist between boots.

## Expected Proof

Inside the guest, these checks should succeed:

```sh
cat /proc/1/comm
systemctl is-system-running || true
chromium --headless --no-sandbox --disable-gpu --version
claude --version
mountpoint /workspace/react-app
```

This demonstrates a full Debian agent environment rather than the older
`init.krun` workload path: systemd is PID 1, normal services are running,
Chromium is installed, Claude Code is available to the `agent` user, and the
React app is a host-mounted workspace.
