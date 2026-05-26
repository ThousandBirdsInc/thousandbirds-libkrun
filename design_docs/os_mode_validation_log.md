# OS Mode Validation Log

Use this file as the running evidence log for OS-mode runtime gates. Do not mark
runtime TODO items in `full_linux_os_mode.md` complete until the relevant row
below contains command output, host details, guest image details, and readiness
markers.

## Local Build Evidence

- Host: Darwin `25.4.0`, arm64, macOS/ARM64 HVF-capable host.
- macOS: `26.4.1` build `25E253`.
- Host CPU/model: Apple M5 Max, `Mac17,7`.
- Installed host tools:
  - Homebrew `e2fsprogs 1.47.4`
  - Homebrew `qemu 11.0.0`
  - Homebrew `xz 5.8.3`
  - Homebrew `zig 0.16.0_1`
  - Homebrew `podman 5.8.2`
  - Homebrew `vfkit 0.6.3`
  - Homebrew `fakeroot 1.37.2`
  - Homebrew `e2tools 0.1.2`
  - Homebrew `squashfs 4.7.5`
- `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --features 'blk net' --lib`: passed, 17 tests.
- `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib`: passed, 12 tests.
- Latest recheck after persistent-control and larger-root validation changes:
  - `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --features 'blk net' --lib`: passed, 17 tests.
  - `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib`: passed, 12 tests.
- Latest recheck after manifest overlay-consistency validation changes:
  - `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --features 'blk net' --lib`: passed, 17 tests.
  - `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib`: passed, 12 tests.
- `cargo fmt --manifest-path src/libkrun/Cargo.toml --check`: passed.
- `cargo fmt -p krun-vmm --check`: passed after the console command-line fix.
- `cargo fmt -p krun-devices --check`: passed after the aarch64 PL011 FDT fix.
- `cargo fmt --manifest-path src/hvf/Cargo.toml --check`: passed after HVF 16-bit MMIO write support.
- `cc -fsyntax-only -Iinclude examples/os_mode.c`: passed with pre-existing header comment warnings.
- `cc -fsyntax-only -Iinclude examples/os_mode.c`: passed after adding the `--disk-sync` launcher option.
- `sh -n examples/os_mode_apfs_clone.sh`: passed.
- `sh -n examples/os_mode_apfs_validate.sh`: passed after changing clone/full-copy timing to monotonic milliseconds.
- `examples/os_mode_apfs_validate.sh /private/tmp/libkrun-osmode-apfs-timing 8`: passed after the temporary-file publish change with `mode=clone`, clone `elapsed_ms=23`, full-copy `full_copy_elapsed_ms=18`, base checksum stable, and `cleanup=ok`.
- APFS clone no-overwrite check: passed. With a pre-existing destination, `examples/os_mode_apfs_clone.sh` failed before cloning and printed `Clone destination already exists`.
- `python3 -m py_compile examples/os_mode_build_container_rootfs.py examples/os_mode_smoke.py examples/os_mode_perf.py`: passed.
- `python3 -m py_compile examples/os_mode_build_container_rootfs.py examples/os_mode_smoke.py examples/os_mode_perf.py examples/os_mode_manifest_check.py`: passed after adding the manifest checker.
- `examples/os_mode_manifest_check.py --require-apfs /private/tmp/libkrun-osmode-manifest-check/manifest.json`: passed against a synthetic manifest with matching rootfs/root-disk checksums, APFS metadata, and generated commands.
- Manifest checker checksum-negative self-test: passed; a synthetic manifest with a wrong `root_disk_sha256` failed and reported `root_disk checksum mismatch`.
- Builder/checker import self-test: `python3 examples/os_mode_build_container_rootfs.py --help` passed after wiring the builder to call `check_manifest_payload()`.
- Builder manifest emission guard: the builder now validates the manifest payload before writing `manifest.json`, so a failed validation returns nonzero without publishing a new invalid manifest.
- Manifest checker source-identity negative self-test: passed; a synthetic manifest with `source_digest=null` failed and reported `source_digest must be a non-empty string`.
- Manifest checker missing-source-identity negative self-test: passed; a synthetic manifest with no `source_digest` field failed without crashing and reported `missing required field: source_digest`.
- `ci/os_mode_host_checks.sh`: passed. The aggregate host-independent check ran Python helper syntax checks, Python helper import/help checks, shell helper syntax checks, `.dockerignore` context-guard checks, C API syntax, smoke helper marker/timeout self-tests with JSON evidence validation including merged stdout/stderr output, exact root-source validation, console-token validation, and PID 1 `init.krun` rejection, `os_mode_perf.py` control, timeout, exit-wait, and nonzero-exit self-tests with JSON evidence validation, container-rootfs builder positive-size validation, systemd unit-name validation, relative output/kernel/initramfs/overlay path normalization checks, systemd platform-serial-console builder checks, manifest checker positive/negative self-tests, manifest `--check-kernel-paths` positive/negative self-tests, required `kernel`/`kernel_format`/`initramfs`/`init_mode` field checks, builder and runtime allow-list checks, source identity shape checks including Docker/Podman bare SHA-256 image IDs, required APFS output metadata and shape checks, platform allow-list checks, systemd mask metadata and unit-name checks, generated `os_mode_command` kernel/kernel-format/initramfs/arm64-console/amd64-console/systemd consistency checks, duplicate launcher-option rejection, malformed launcher-option value rejection including option-like values, unexpected launcher-argument rejection, command-array string-only checks, checksum-presence negative tests, optional overlay checksum consistency tests, and APFS clone-command destination negative tests. The C syntax step still reports the pre-existing `/dev/input/*` header comment warnings.
- `make os-mode-checks`: passed after making APFS output metadata mandatory in manifests, adding APFS metadata shape validation, documenting the macOS container-image-to-libkrun/HVF OS flow, tightening the container-rootfs manifest platform/console contract for `linux/arm64` and `linux/amd64`, requiring Docker/Podman-style SHA-256 source identities, enforcing the supported Docker/Podman builder runtime contract, recording/verifying kernel format in the generated launch command, normalizing relative builder output, kernel, initramfs, and overlay paths before manifest generation, making systemd getty/control-shell generation use the selected platform serial console instead of hardcoded `ttyAMA0`, and validating `--size-mb` plus configurable systemd mask unit names before the Docker/Podman build step. The C syntax step still reports the pre-existing `/dev/input/*` header comment warnings.
- Latest host-independent recheck after adding the clean-host preflight helper:
  `make os-mode-checks` passed. The aggregate check now compiles and imports
  `examples/os_mode_clean_host_preflight.py`, verifies `--help`, validates a
  synthetic artifact manifest and archive checksum, confirms absent cache and
  fresh output paths pass, and confirms existing cache entries, non-empty cache
  entries, existing/non-empty output directories, and mutable image references
  are rejected before any pull, load, APFS clone, or HVF launch. The publisher
  self-test now also requires artifact manifests to record clean-host preflight
  commands for both registry-image and archive-manifest release paths.
- Latest host-independent recheck after making clean-host preflight evidence a
  required archive artifact: `make os-mode-checks` passed. The release gate now
  requires `--preflight-json` with `--clean-host-baseline`; release evidence can
  copy `clean-host-preflight.json`; the verifier's default Makefile flags now
  require that archived preflight JSON and compare its image reference, absent
  cache entry, fresh output directory, APFS checks, macOS/arm64 host metadata,
  and release-gate command against the release-gate summary. The aggregate
  tests also reject a preflight report whose cache entry existed before launch.
- Latest host-independent recheck after adding the clean-host baseline wrapper:
  `make os-mode-checks` passed. The aggregate check now compiles and imports
  `examples/os_mode_clean_host_baseline.py`, verifies `--help`, verifies the
  wrapper builds matching preflight and release-gate commands from one artifact
  manifest/cache/output/runtime configuration, verifies `--build-command`
  propagation to the release gate, verifies the wrapper executes preflight
  before release gate, verifies preflight refuses to overwrite an existing JSON
  report, and verifies the release gate rejects an explicit IMAGE that does not
  match an artifact manifest `digest_ref`.
- Latest host-independent recheck after timestamping clean-host preflight
  evidence: `make os-mode-checks` passed. `examples/os_mode_clean_host_preflight.py`
  now records `created_at_utc`, release evidence carries that preflight
  timestamp in its summary, and `examples/os_mode_verify_release_evidence.py`
  rejects archives whose preflight timestamp is later than
  `release-evidence.json` `created_at_utc`.
- Latest host-independent recheck after making baseline tables mechanically
  verified: `make os-mode-checks` passed. `examples/os_mode_verify_release_evidence.py`
  now regenerates `baseline.md` with `examples/os_mode_baseline_table.py` from
  the archived release evidence and rejects stale or hand-edited baseline table
  contents before clean-host evidence can be accepted.
- Latest host-independent recheck after tightening release-gate summary path
  verification: `make os-mode-checks` passed. The verifier now rejects archives
  whose `release-gate-summary.json` points at a different `release-evidence.json`
  path, `baseline.md` path, or preflight JSON source than the archive actually
  contains; the aggregate check covers stale baseline-table and preflight-source
  summary paths.
- Latest host-independent recheck after archiving artifact manifests in release
  evidence: `make os-mode-checks` passed. `examples/os_mode_collect_release_evidence.py`
  can now copy a `libkrun.os-bundle.artifact.v1` manifest into
  `artifact-manifest.json`, `examples/os_mode_release_gate.py` supplies that
  manifest for archive-delivered gates, and
  `examples/os_mode_verify_release_evidence.py --require-artifact-manifest`
  verifies the copied manifest checksum, source path, `kind`, and `digest_ref`
  against the release evidence image reference.
- Local clean-host baseline wrapper print-only check passed against the durable
  Debian systemd artifact manifest. The printed command pair used
  `examples/os_mode_clean_host_preflight.py --artifact-manifest ... --json-output
  os_mode_artifacts/debian-systemd-bookworm-arm64/preflight-clean-host-local.json`
  followed by `examples/os_mode_release_gate.py --artifact-manifest ...
  --preflight-json
  os_mode_artifacts/debian-systemd-bookworm-arm64/preflight-clean-host-local.json
  --clean-host-baseline`, with the same cache and evidence output paths.
  `--print-only` did not pull, load, APFS-clone, or boot.
- Local clean-host preflight timestamp sample passed against the durable Debian
  systemd artifact manifest and wrote
  `os_mode_artifacts/debian-systemd-bookworm-arm64/preflight-clean-host-local-timestamp.json`.
  The report includes `created_at_utc`, APFS cache/output checks, artifact
  archive SHA-256 validation, an absent cache entry, a fresh output directory,
  and the matching `--clean-host-baseline --preflight-json` release-gate
  command. This remains preflight-only evidence, not the final clean-host
  performance baseline.
- Local clean-host preflight sample against the durable Debian systemd artifact
  manifest passed:
  `examples/os_mode_clean_host_preflight.py --artifact-manifest
  os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
  --cache-dir os_mode_artifacts/preflight-cache-clean-host --output-dir
  os_mode_artifacts/debian-systemd-bookworm-arm64/preflight-clean-host-local
  --json-output
  os_mode_artifacts/debian-systemd-bookworm-arm64/preflight-clean-host-local.json`.
  The report recorded macOS/arm64 host metadata, APFS cache/output ancestors,
  Docker selected from `auto`, valid artifact archive SHA-256, absent derived
  cache entry, fresh output path, and the exact `--clean-host-baseline`
  release-gate command with `--preflight-json`. This is a preflight only and
  does not replace the remaining true clean Apple Silicon host baseline.
- Latest host-independent recheck after adding manifest `expected_root` and
  `--smoke-output` command printing: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py examples/os_mode_manifest_check.py
  examples/os_mode_smoke.py examples/os_mode_perf.py`, shell syntax checks,
  and `make os-mode-checks` all passed. The aggregate checks now require
  container-derived manifests to carry an expected root-source marker, print
  smoke wrappers that pass `--expect-root`, and cover `--smoke-output` positive
  and negative argument handling so replayed macOS/HVF smoke commands can write
  JSON evidence next to the manifest.
- Latest host-independent recheck after adding manifest smoke-timeout evidence:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now require `smoke_timeout_sec` in
  container-derived manifests, reject non-positive smoke timeouts, and verify
  printed smoke replay commands pass the manifest timeout to
  `os_mode_smoke.py --timeout`.
- Latest host-independent recheck after adding manifest smoke poweroff policy:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now require `smoke_poweroff_after_ready` in
  container-derived manifests, reject non-boolean values, verify the smoke
  replay command appends `--poweroff-after-ready` by default, and verify the
  production `os_mode_command` remains distinct from the smoke-only poweroff
  behavior.
- Latest host-independent recheck after adding smoke-helper post-ready exit
  waits: `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now cover `os_mode_smoke.py
  --wait-exit-after-ready` argument validation, successful post-ready process
  exit, post-ready exit timeout failure, manifest
  `smoke_wait_exit_after_ready_sec` validation, and printed smoke replay
  commands that require the VMM to exit after readiness when smoke poweroff is
  enabled.
- Latest host-independent recheck after adding manifest replay runbook writing:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now cover `--write-runbook`, verify the
  generated shell script is executable and passes `sh -n`, and confirm it
  contains the validated APFS clone command followed by the smoke command with
  JSON evidence, expected root, console, post-ready exit wait, and smoke-only
  poweroff behavior.
- Latest host-independent recheck after hardening manifest replay runbook
  writing: `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `--write-runbook` refuses an
  existing destination and refuses paths that resolve to protected manifest
  artifacts, including `root.raw` and the APFS clone destination.
- Latest host-independent recheck after hardening smoke JSON output paths:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `--smoke-output` refuses
  protected manifest artifact paths, including `root.raw` and the APFS clone
  destination, and verify `--write-runbook` refuses to use the same path as
  `--smoke-output`.
- Latest host-independent recheck after adding output-parent validation:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `--smoke-output` and
  `--write-runbook` reject paths whose parent directories do not exist, so
  replay validation fails before boot or runbook creation rather than after a
  guest has started.
- Latest host-independent recheck after adding smoke JSON overwrite
  protection: `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `--smoke-output` refuses an
  existing destination so replayed validation cannot silently overwrite prior
  JSON evidence.
- Latest host-independent recheck after adding APFS clone-destination
  preflight for printed commands: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py examples/os_mode_manifest_check.py
  examples/os_mode_smoke.py examples/os_mode_perf.py`, shell syntax checks,
  and `make os-mode-checks` all passed. The aggregate checks now verify
  `--print-commands` fails before replay when the manifest default clone
  destination or a `--clone-dest` override already exists, and verify
  `--clone-dest` rejects missing parent directories.
- Latest host-independent recheck after hardening direct smoke JSON output:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify direct `os_mode_smoke.py
  --output` rejects missing parent directories and existing files before the
  smoke command can launch a guest.
- Latest host-independent recheck after hardening direct perf JSON output:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify direct `os_mode_perf.py --output`
  rejects missing parent directories and existing files before the timing
  command can launch a guest.
- Latest host-independent recheck after adding container-rootfs output
  artifact preflight: `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify the builder identifies stale
  `rootfs.tar`, `overlay.tar`, `root.raw`, `vm-root.raw`, and `manifest.json`
  output artifacts before runtime probing, container pulls, export, or ext4
  build starts.
- Latest host-independent recheck after adding Linux smoke console assertions:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The Linux KVM validation wrapper now validates
  `KRUN_OSMODE_EXPECT_CONSOLE` as a single kernel-command-line token, defaults
  it to `KRUN_OSMODE_CONSOLE`, and passes it to
  `os_mode_smoke.py --expect-console` for every KVM smoke command shape.
- Latest host-independent recheck after adding performance-helper OS invariant
  guards: `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `os_mode_perf.py --expect-root`,
  `os_mode_perf.py --expect-console`, and PID 1 `init.krun` rejection so timing
  evidence cannot be recorded as successful for the wrong root, wrong console,
  or workload-mode init path.
- Latest host-independent recheck after requiring perf invariant markers:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `os_mode_perf.py --expect-root`
  fails with `missing-root-marker` when no root marker appears and
  `--expect-console` fails with `missing-console-marker` when no console marker
  appears. The helper also supports `--require-pid1-marker`, and manifest
  generated perf replay commands pass it so timing evidence fails with
  `missing-pid1-marker` when no PID 1 marker appears.
- Latest host-independent recheck after adding manifest-generated perf replay:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The manifest checker now supports `--perf-output` with fresh
  output-path validation, empty-path rejection, protected artifact checks,
  smoke/perf/runbook collision checks, and printed `os_mode_perf.py` replay
  commands that include manifest timeout, expected root, and expected console
  assertions.
- Latest host-independent recheck after wiring perf replay into runbooks:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now verify `--write-runbook` appends the
  guarded `os_mode_perf.py` command when `--perf-output` is provided and keeps
  the smoke-only `--poweroff-after-ready` flag out of that perf command.
- Latest host-independent recheck after moving protected APFS clone destination
  checks into manifest validation: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The aggregate checks now include manifests whose default clone
  destination resolves to `rootfs.tar`, `overlay.tar`, the manifest file
  itself, or `root.raw`, and validation rejects them before command printing.
- Latest host-independent recheck after adding builder-image identity to the
  container-rootfs manifest contract: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `builder_image` and `builder_digest`,
  and the manifest checker requires a valid Docker/Podman SHA-256 identity for
  the builder image as well as the source OS image.
- Latest host-independent recheck after adding container runtime version
  capture to the manifest contract: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `runtime_version`, and the manifest
  checker requires it to be a non-empty string so root-disk artifacts identify
  the Docker or Podman version used for export/build operations.
- Latest host-independent recheck after adding artifact-size validation to
  container-rootfs manifests: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `rootfs_tar_size_bytes`,
  `root_disk_size_bytes`, and optional `overlay_tar_size_bytes`, and the
  manifest checker validates those sizes alongside checksums so truncated or
  swapped artifacts fail before boot.
- Latest host-independent recheck after adding requested root-disk-size
  validation: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `root_disk_size_mb`, and the manifest
  checker verifies `root_disk_size_bytes` equals that MiB value so `--size-mb`
  is enforced before launch.
- Latest host-independent recheck after adding build-host metadata to the
  container-rootfs manifest contract: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records host system, release, machine, and Python
  version, and the manifest checker requires those fields so generated
  macOS/container artifacts carry host provenance.
- Latest host-independent recheck after adding the container-rootfs manifest
  schema version: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `manifest_schema_version=1`, and the
  manifest checker rejects unsupported versions before replaying clone, smoke,
  or perf commands.
- Latest host-independent recheck after tightening manifest timing evidence:
  `python3 -m py_compile examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The manifest checker now rejects boolean timing values and
  `timings_ms.total` values smaller than `export_rootfs + build_ext4`.
- Latest host-independent recheck after adding UTC creation timestamps to
  container-rootfs manifests: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `created_at_utc`, and the manifest
  checker requires an ISO 8601 UTC timestamp ending in `Z`.
- Latest host-independent recheck after adding builder-script provenance to
  container-rootfs manifests: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The builder now records `builder_script_sha256`, and the
  manifest checker requires a SHA-256-shaped value so generated root disks can
  be tied back to the rootfs mutation and ext4 construction script.
- Latest host-independent recheck after making manifest command printing
  preflight boot artifact paths: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. `--print-commands` now implies kernel/initramfs path validation
  for non-null manifest fields, so replay and runbook generation fail before
  printing commands for missing boot artifacts.
- Latest host-independent recheck after rejecting boolean numeric manifest
  fields for schema and kernel format: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. The manifest checker now rejects JSON booleans for
  `manifest_schema_version` and `kernel_format` instead of accepting them as
  Python integers.
- Latest host-independent recheck after adding replay-helper existence
  preflights to manifest command printing: `python3 -m py_compile
  examples/os_mode_build_container_rootfs.py
  examples/os_mode_manifest_check.py examples/os_mode_smoke.py
  examples/os_mode_perf.py`, shell syntax checks, and `make os-mode-checks`
  all passed. `--print-commands` now verifies the APFS clone and smoke/perf
  helper scripts exist before printing replay or runbook commands.
- Latest documentation alignment pass for the macOS container-to-VM path:
  `git diff --check`, unchecked-TODO scan for `full_linux_os_mode.md`, and
  `make os-mode-checks` all passed. `design_docs/os_mode_guest_image.md` now
  describes Docker/Podman as the macOS Linux filesystem/export builder, APFS as
  the per-VM CoW disk provisioning layer, and libkrun/HVF as the runtime proof;
  its manifest example includes the current schema/provenance/artifact-size,
  APFS clone, and generated command fields.
- Top-level README OS-mode quickstart pass: `git diff --check`, unchecked-TODO
  scan for `full_linux_os_mode.md`, and `make os-mode-checks` all passed after
  adding a repo-root example for the macOS OCI-image-to-raw-ext4-to-APFS-clone
  workflow and manifest-generated smoke runbook.
- OS-mode virtio-fs root-tag guard: `env KRUN_INIT_BINARY_PATH=/bin/echo cargo
  test -p libkrun --features 'blk net' --lib` passed with 23 tests, `env
  KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib` passed with 15
  tests, `cc -fsyntax-only -Iinclude examples/os_mode.c`, `cargo fmt
  --manifest-path src/libkrun/Cargo.toml --check`, `git diff --check`, and
  `make os-mode-checks` all passed. OS mode now rejects
  `krun_add_virtiofs*()` with `KRUN_FS_ROOT_TAG` (`/dev/root`) while preserving
  non-root virtio-fs mounts for explicit shared filesystems.
- OS-mode console-token API guard: `env KRUN_INIT_BINARY_PATH=/bin/echo cargo
  test -p libkrun --features 'blk net' --lib` passed with 25 tests, `env
  KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib` passed with 17
  tests, `cc -fsyntax-only -Iinclude examples/os_mode.c`, `cargo fmt
  --manifest-path src/libkrun/Cargo.toml --check`, `git diff --check`, and
  `make os-mode-checks` all passed. OS mode now rejects
  `krun_set_kernel_console()` values that would split into multiple kernel
  command-line tokens, including invalid console overrides set before
  `krun_set_os_mode()`.
- OS-mode embedded-DHCP ordering guard: `env KRUN_INIT_BINARY_PATH=/bin/echo
  cargo test -p libkrun --features 'blk net' --lib` passed with 26 tests,
  `env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib` passed with
  17 tests, `cc -fsyntax-only -Iinclude examples/os_mode.c`, `cargo fmt
  --manifest-path src/libkrun/Cargo.toml --check`, `git diff --check`, and
  `make os-mode-checks` all passed. OS mode now rejects pre-existing
  `NET_FLAG_DHCP_CLIENT` state because it would ask libkrun's workload init to
  configure networking, while OS-mode guests must run their own DHCP or static
  network setup.
- OS-mode TSI/vsock ordering guard: `env KRUN_INIT_BINARY_PATH=/bin/echo cargo
  test -p libkrun --features 'blk net' --lib` passed with 31 tests, `env
  KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib` passed with 22
  tests, `cc -fsyntax-only -Iinclude examples/os_mode.c`, `cargo fmt
  --manifest-path src/libkrun/Cargo.toml --check`, `git diff --check`, and
  `make os-mode-checks` all passed. OS mode now rejects TSI port maps and TSI
  hijacking, including state set before `krun_set_os_mode()`, while still
  allowing explicit plain vsock devices with no TSI hijacking.
- OS-mode vsock IPC explicit-device guard: `env KRUN_INIT_BINARY_PATH=/bin/echo
  cargo test -p libkrun --features 'blk net' --lib` passed with 35 tests, `env
  KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --lib` passed with 26
  tests, `cc -fsyntax-only -Iinclude examples/os_mode.c`, `cargo fmt
  --manifest-path src/libkrun/Cargo.toml --check`, `git diff --check`, and
  `make os-mode-checks` all passed. OS mode now requires
  `krun_add_vsock_port*()` state to use an explicit non-TSI vsock device,
  including state configured before `krun_set_os_mode()`, so implicit-vsock IPC
  maps cannot be silently dropped when OS mode disables implicit vsock.
- GitHub Actions wiring: `.github/workflows/code-quality.yml` now runs `make os-mode-checks` in the Linux x86_64, Linux aarch64, and macOS code-quality jobs. Local YAML parse with Ruby passed.
- Docker context guard: `.dockerignore` now excludes local Cargo outputs, sysroots, generated example binaries, dylibs/shared objects, and root-disk image formats. This prevents the Linux Docker validation build context from including local artifacts such as the current `target` tree (`3.2 GiB`) and `examples/target` (`829 MiB`).
- Docker validation wrapper hardening: `ci/os_mode_linux_validate.sh` now fails clearly when it is not run from the libkrun repo root, supports `KRUN_OSMODE_HOST_CHECKS`, and falls back to `/usr/local/bin/os_mode_host_checks.sh`; `ci/os_mode_linux.Dockerfile` copies the host-check script into that fallback path.
- Git ignore hygiene: `.gitignore` now ignores `examples/os_mode` and `*.dSYM`; `git check-ignore -v examples/os_mode examples/os_mode.dSYM` reports the expected ignore rules.
- Example cleanup hygiene: `examples/Makefile clean` now removes `*.dSYM` bundles in addition to example binaries and rootfs output.
- `examples/os_mode_smoke.py` marker self-test: passed with synthetic `KRUN_OSMODE:*` output and JSON evidence recording `ready=true`, no missing markers, non-negative elapsed time, and captured output lines.
- `examples/os_mode_smoke.py` timeout self-test: passed; a child that printed a partial line and slept was terminated after timeout and JSON evidence recorded `ready=false`, `failure_reason=missing-markers`, a missing ready marker, and the partial output line.
- `examples/os_mode_smoke.py` root guard self-test: passed; synthetic output
  with `KRUN_OSMODE: root=/dev/vda10 ext4 rw` failed when `--expect-root
  /dev/vda1` was set, proving the helper compares the root source token instead
  of doing substring matching.
- `examples/os_mode_smoke.py` console guard self-test: passed; synthetic output
  with `KRUN_OSMODE: console=ttyAMA0` failed when `--expect-console ttyS0` was
  set.
- `examples/os_mode_smoke.py` PID 1 guard self-test: passed; synthetic output
  with `KRUN_OSMODE: pid1=init.krun /init.krun` failed and JSON evidence
  recorded `failure_reason=pid1-init.krun`.
- `examples/os_mode_perf.py` control self-test: passed; fake guest emitted
  `KRUN_OSMODE: ready`, accepted `--control-command`, emitted
  `KRUN_OSMODE: control=ok`, and JSON evidence recorded ready/control timing,
  markers, and output lines.
- `examples/os_mode_perf.py` timeout self-test: passed; fake guest emitted
  `KRUN_OSMODE: ready` without the expected control marker, and the helper
  terminated it at the configured timeout with exit code `1`. JSON evidence
  recorded ready timing without a control timing.
- `examples/os_mode_perf.py` exit-wait self-test: passed; fake guest emitted
  `KRUN_OSMODE: ready` but did not exit before `--wait-exit-after-ready`
  expired, and JSON evidence recorded `failure_reason=exit-timeout`.
- `examples/os_mode_perf.py` nonzero-exit self-test: passed; fake guest emitted
  `KRUN_OSMODE: ready` and exited with status `7` before the post-ready wait
  expired, and JSON evidence recorded `failure_reason=exit-nonzero`.
- Latest host-independent recheck after adding the pull-to-launch OCI OS bundle
  importer: `make os-mode-checks` passed. The aggregate checks now compile and
  import `examples/os_mode_import_container_bundle.py`, validate a synthetic
  `libkrun.os-bundle.v1` directory with `kernel`, `initramfs`, `root.raw`, and
  `manifest.json`, verify the printed APFS clone, host-side `examples/os_mode`,
  and smoke-wrapper commands, and reject bad bundle manifests for wrong kind,
  unsupported platform, console mismatch, unsafe root paths, whitespace-split
  root tokens, checksum mismatch, root size mismatch, `expected_pid1=init.krun`,
  full-copy fallback, unsafe `../` bundle paths, existing clone destinations,
  immutable `root.raw` clone destinations, and missing strict source digest.
- Latest host-independent recheck after adding the OCI OS bundle publisher:
  `make os-mode-checks` passed. The aggregate checks now compile and import
  `examples/os_mode_publish_container_bundle.py`, publish the synthetic
  container-derived manifest into a Docker-compatible bundle context with
  `Containerfile`, `libkrun-os-bundle/root.raw`, `kernel`, `initramfs`, and
  bundle `manifest.json`, validate that published bundle through
  `examples/os_mode_import_container_bundle.py`, and reject stale output
  directories, `--expected-pid1 init.krun`, and source manifests whose launch
  command attaches the immutable base root directly.
- Latest host-independent recheck after adding PID 1 allow-list smoke
  validation: `make os-mode-checks` passed. The aggregate checks now cover
  `examples/os_mode_smoke.py --expect-pid1`, verify mismatched PID 1 markers
  fail with `failure_reason=pid1-mismatch`, and verify bundle importer smoke
  commands include `--expect-pid1` from the bundle manifest.
- Latest host-independent recheck after adding bundle smoke-evidence
  enrichment: `make os-mode-checks` passed. The aggregate checks now call
  `examples/os_mode_import_container_bundle.py`'s evidence enrichment path
  against synthetic smoke JSON and verify the resulting evidence contains
  source image identity, APFS clone destination, expected PID 1, and the
  host-side `examples/os_mode` command.
- Latest host-independent recheck after adding bundle importer perf command
  printing: `make os-mode-checks` passed. The aggregate checks now require
  `examples/os_mode_import_container_bundle.py --perf-output` to print a
  guarded `examples/os_mode_perf.py` command with output path,
  `--require-pid1-marker`, expected root, and expected console, and verify the
  perf command does not include the smoke-only `--poweroff-after-ready` flag.
  Negative checks reject existing perf evidence paths, protected root-disk
  paths, and smoke/perf evidence path collisions.
- Latest host-independent recheck after adding bundle root-disk allocated-size
  tracking: `make os-mode-checks` passed. The aggregate checks now require the
  synthetic bundle manifest and published bundle manifest to record
  `root_disk_allocated_bytes`, reject mismatched allocation metadata when the
  host reports `st_blocks`, and verify enriched smoke evidence includes the
  observed immutable root-disk allocation.
- Latest host-independent recheck after defining digest-pinned remote bundle
  publication/consumption: `make os-mode-checks` passed. The aggregate checks
  now verify `examples/os_mode_import_container_bundle.py --strict-digest
  --image ...` rejects mutable image tags, verify digest-pinned image reference
  parsing accepts `image@sha256:...`, and verify
  `examples/os_mode_publish_container_bundle.py` rejects `--push` without
  `--image-tag`, rejects `--digest-output` without `--push`, and writes digest
  output files without overwriting existing evidence.
- Bundle evidence policy: successful pull-to-launch smoke/perf evidence should
  be stored as standalone JSON artifacts next to the extracted bundle or
  validation run directory. This log should reference those artifact paths and
  summarize key markers/timings instead of embedding the full smoke JSON.
- Latest host-independent recheck after adding bundle runtime evidence
  metadata: `make os-mode-checks` passed. The aggregate checks now verify
  `examples/os_mode_smoke.py` records launcher and child process PIDs, and
  verify bundle smoke evidence enrichment records imported image reference plus
  importer-side extraction/APFS-clone/smoke/total timing metadata.
- Latest host-independent recheck after documenting the macOS OCI OS-bundle
  product path and Phase 22 release gates: `make os-mode-checks` passed on
  macOS. This rechecked Python helper syntax/imports, bundle importer and
  publisher self-tests, shell helper syntax, Linux validation argument guards,
  APFS clone helper guards, Docker context guard, C API syntax,
  smoke/perf helper guards, marker parsing, manifest validation, bundle
  validation, and generated command checks.
- Latest host-independent recheck after adding structured observed smoke and
  perf evidence: `make os-mode-checks` passed on macOS. The aggregate smoke
  and perf helper self-tests now verify JSON fields for `observed_root`,
  `observed_root_line`, `observed_pid1`, `observed_pid1_line`,
  `observed_console`, `observed_consoles`, `observed_network`, and the
  `observed` marker map.
- Latest host-independent recheck after hardening bundle smoke evidence
  enrichment: `make os-mode-checks` passed on macOS. The bundle importer
  self-test now verifies enriched smoke JSON must contain `ready=true` and
  structured observed root, console, and PID 1 values matching the bundle
  manifest. Synthetic `ready=false`, observed-root mismatch, observed-console
  mismatch, observed-PID1 mismatch, and observed `init.krun` PID 1 cases are
  rejected before bundle metadata is written.
- Local completion audit recorded in `design_docs/full_linux_os_mode.md`: the
  implemented macOS path covers OS-mode PID 1 handoff, container-rootfs
  authoring, OCI OS-bundle consumption, APFS CoW launch, structured
  smoke/perf evidence, and explicit Linux/KVM deferral. The audit does not mark
  the full design complete because Linux/KVM runtime and workload-mode runtime
  regression remain dependent on unavailable host artifacts.
- Guest-image companion doc alignment: `design_docs/os_mode_guest_image.md`
  now treats OCI-packaged OS bundles as the preferred macOS consumption path
  and container-rootfs export as the authoring path. It documents bundle layout,
  importer command, manifest contract, cache/reuse behavior, local bundle
  publishing, known-good macOS bundle profiles, and the continued Linux/KVM
  runtime deferral.
- `make BLK=1 NET=1` on macOS: passed with:
  - `CC_LINUX=/opt/homebrew/opt/llvm@21/bin/clang -target aarch64-linux-gnu -fuse-ld=/opt/homebrew/opt/lld@21/bin/ld.lld ...`
  - `LIBCLANG_PATH=/opt/homebrew/opt/llvm@21/lib`
  - local build-artifact symlink `target/release/deps/libclang.dylib -> /opt/homebrew/opt/llvm@21/lib/libclang.dylib`
- `make -C examples os_mode LDFLAGS_arm64_Darwin='-L../target/release -lkrun'`: passed.
- Local runtime symlink used for the example during validation:
  `libkrun.1.dylib -> target/release/libkrun.1.18.0.dylib`; generated
  example binaries, dSYM output, dylib symlinks, and Python caches were removed
  from the repo workspace after validation.

## Linux Compile Gate

- Status: passed in a Linux Docker container on Docker Desktop for macOS.
- Caveat: this validates Linux userspace build/test behavior, not Linux/KVM
  runtime behavior. KVM smoke still requires a Linux host or Linux CI runner
  with `/dev/kvm` passed into the container.
- Docker compile gate added:
  ```sh
  docker build -f ci/os_mode_linux.Dockerfile -t libkrun-os-mode-linux .
  docker run --rm -v "$PWD:/workspace/libkrun" libkrun-os-mode-linux
  ```
- Docker compile gate result:
  ```text
  ==> cargo unit tests: blk net
  test result: ok. 17 passed; 0 failed
  ==> C API compile check
  ==> release build
  Finished `release` profile [optimized]
  ==> example build
  ==> skipping KVM smoke; set RUN_KVM_SMOKE=1 and pass --device /dev/kvm to Docker
  ```
- Command to run directly on Linux:
  ```sh
  env KRUN_INIT_BINARY_PATH=/bin/echo cargo test -p libkrun --features 'blk net' --lib
  cc -fsyntax-only -Iinclude examples/os_mode.c
  ```

## Linux/KVM Boot

- Status: deferred until a real Linux host or Linux CI runner with `/dev/kvm`
  is available.
- Host:
- libkrun build flags:
- Guest kernel version:
- Guest kernel config:
- Root image checksum:
- Root image source:
- Command:
- Readiness markers:
- Result:

## macOS/ARM64 HVF Boot

- Status: passed.
- Host: Darwin `25.4.0`, arm64, macOS `26.4.1` build `25E253`,
  Apple M5 Max, `Mac17,7`.
- libkrun build flags: `BLK=1 NET=1`, local release dylib.
- Guest kernel version: Alpine Linux `6.18.22-0-virt`, downloaded from the
  official Alpine `latest-stable` aarch64 netboot directory on 2026-05-16.
- Guest kernel config:
  `/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/config-6.18.22-0-virt`
- Guest artifact paths:
  - Kernel:
    `/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt`
  - Custom initramfs:
    `/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz`
  - Root disk:
    `/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/rootfs-smoke-v2.ext4`
- Artifact checksums:
  ```text
  624f12e57616ce2ac425eafb265a38f0fb037a371baf99ac75fe46c05167e1cf  vmlinuz-virt
  3262d2c209e8a6eb4f64be396d54bf332ed8ae17c3c144e2ab96344960fc6764  initramfs-virt-with-ext4.gz
  98ff3c7cb60ec791aa8dd5b26925286e296a1e9a2f19bdb9fd5f0f3da353c47e  rootfs-smoke-v2.ext4
  ```
- Root image source: Alpine `3.23.4` aarch64 minirootfs, with a BusyBox
  `/etc/inittab` smoke override that emits `KRUN_OSMODE:*` markers. The custom initramfs merges Alpine's
  `modloop-virt` modules into `initramfs-virt` so ext4 can be mounted before
  `switch_root`.
- QEMU/HVF control command:
  ```sh
  qemu-system-aarch64 \
    -machine virt,accel=hvf -cpu host -m 512M -smp 1 -nographic -no-reboot \
    -kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    -initrd /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
    -append 'console=ttyAMA0 root=/dev/vda rootfstype=ext4 rw init=/sbin/init modules=ext4' \
    -drive file=/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/rootfs-smoke-v2.ext4,if=none,format=raw,id=root \
    -device virtio-blk-device,drive=root
  ```
- QEMU/HVF readiness markers:
  ```text
  virtio_blk virtio1: [vda] 524288 512-byte logical blocks (268 MB/256 MiB)
  EXT4-fs (vda): mounted filesystem ... ro with ordered data mode.
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 ro,relatime
  KRUN_OSMODE: pid1=init
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: ready
  ```
- libkrun command:
  ```sh
  examples/os_mode \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --kernel-format 2 \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
    --root-disk /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/rootfs-libkrun-v2.ext4 \
    --root-device /dev/vda \
    --kernel-cmdline 'modules=ext4' \
    --console ttyAMA0
  ```
- libkrun result:
  ```text
  Kernel command line: modules=ext4  root=/dev/vda rootfstype=ext4 init=/sbin/init console=ttyAMA0 earlycon=pl011,mmio32,0x0a001000
  a001000.pl011: ttyAMA0 at MMIO 0xa001000 (irq = 13, base_baud = 0) is a PL011 rev1
  printk: console [ttyAMA0] enabled
  virtio_blk virtio3: [vda] 524288 512-byte logical blocks (268 MB/256 MiB)
  EXT4-fs (vda): mounted filesystem ... ro with ordered data mode.
  Mounting root: ok.
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 ro,relatime
  KRUN_OSMODE: pid1=init
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: ready
  KRUN_INTERACTIVE_OK
  reboot: Power down
  ```
- Reboot command:
  ```sh
  examples/os_mode_perf.py --timeout 30 --label macos-hvf-reboot \
    --output /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/perf-reboot.json \
    --shutdown-command 'reboot -f' -- examples/os_mode ...
  ```
- Reboot result:
  ```json
  {"exit_code": 0, "elapsed_ms": 448, "ready_ms": 445}
  ```
- Result: libkrun/HVF boot from an APFS clone passed. PID 1 is the guest
  BusyBox init, root is `/dev/vda`, normal PL011 `ttyAMA0` console is active,
  interactive serial input works, `poweroff -f` exits the VMM, and `reboot -f`
  exits the VMM with code 0 on the current HVF path.

## APFS Clone Boot

- Status: host-side clone mechanics validated; libkrun/HVF boot from an APFS
  clone validated; guest write validation passed.
- Base image: `/private/tmp/libkrun-osmode-apfs-test/base.raw`, 16 MiB temporary raw file.
- Clone path: `/private/tmp/libkrun-osmode-apfs-test/clone.raw`
- Clone command output:
  ```text
  mode=clone
  elapsed_ms=0
  allocated_kib=16384
  clone=/private/tmp/libkrun-osmode-apfs-test/clone.raw
  KRUN_OSMODE_APFS: writing clone
  full_copy_elapsed_ms=0
  full_copy_allocated_kib=16384
  clone_allocated_before_kib=16384
  clone_allocated_after_write_kib=16384
  base_sha256=080acf35a507ac9849cfcba47dc2ad83e01b75663a516279c8b9d243b719643e
  cleanup=ok
  ```
- Guest-write boot command:
  ```sh
  examples/os_mode \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --kernel-format 2 \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
    --root-disk /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/rootfs-write-clone.ext4 \
    --root-device /dev/vda \
    --kernel-cmdline 'modules=ext4' \
    --console ttyAMA0
  ```
- Base checksum before: `080acf35a507ac9849cfcba47dc2ad83e01b75663a516279c8b9d243b719643e`
- Base checksum after: unchanged after host-side clone write.
- Guest-write base checksum before:
  `0b15550d7d5a71a8c823c694c496c7c8f952150c075b7e854ffba1cc5be321e7`
- Guest-write base checksum after:
  `0b15550d7d5a71a8c823c694c496c7c8f952150c075b7e854ffba1cc5be321e7`
- Guest-write clone checksum after:
  `260b68e093130f71a12f9788e4104f25f8cd71c9f0207dc70eb06562b2dfda75`
- Guest-write markers:
  ```text
  KRUN_OSMODE: write=ok
  KRUN_OSMODE: ready
  reboot: Power down
  KRUN_HOST: ready=True write_ok=True exit_code=0 elapsed_ms=965
  ```
- Guest-write marker file in clone:
  ```text
  krun-apfs-write-marker
  ```
- Clone allocated size before boot: `262144 KiB` for the 256 MiB write-smoke
  image as reported by `du -k`.
- Clone allocated size after guest writes: `262144 KiB` as reported by `du -k`.
  APFS `du` does not expose per-file unique clone extents; validation records
  clone checksum divergence and successful clone deletion instead.
- Cleanup result: host-side clone cleanup passed.
- OS-mode root clone:
  ```text
  mode=clone
  elapsed_ms=0
  allocated_kib=82080
  clone=/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/rootfs-libkrun-v2.ext4
  ```
- Clone checksum before boot:
  `98ff3c7cb60ec791aa8dd5b26925286e296a1e9a2f19bdb9fd5f0f3da353c47e`
- Clone boot result: libkrun/HVF mounted `/dev/vda` from
  `rootfs-libkrun-v2.ext4` and reached `KRUN_OSMODE: ready`.
- Guest-write clone cleanup result: `rootfs-write-clone.ext4` was deleted
  after VM exit and `test ! -e` passed.

## Container-Derived Root Disk on macOS

- Status: passed for Alpine aarch64 smoke OS mode. Debian systemd
  container-derived full-distro validation is recorded in the next section.
- Host: Darwin `25.4.0`, arm64, macOS `26.4.1` build `25E253`,
  Apple M5 Max, `Mac17,7`.
- Build/export runtime:
  - Docker Desktop `4.63.0`
  - Docker Engine `29.2.1`
  - Platform: `linux/arm64`
- Builder: `examples/os_mode_build_container_rootfs.py`
- Source image: `alpine:3.23`
- Source digest:
  `alpine@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11`
- Guest kernel and initramfs:
  - `/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt`
  - `/private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz`
- Tool check:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image alpine:3.23 \
    --output-dir /private/tmp/libkrun-osmode-container-test \
    --check-tools
  ```
  Result: chose Docker after detecting the local Podman machine was not
  running, then printed `runtime=docker`.
- APFS/DHCP preflight check:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image alpine:3.23 \
    --output-dir /private/tmp/libkrun-osmode-preflight-test \
    --runtime auto \
    --require-apfs-output \
    --check-tools
  ```
  Result:
  ```text
  runtime=docker
  output_dir_apfs={"checked": true, "device": "/dev/disk3s5", "filesystem": "apfs", "is_apfs": true, "mount_point": "/System/Volumes/Data"}
  ```
- APFS clone helper preflight check:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-container-alpine-net/root.raw \
    /private/tmp/libkrun-osmode-preflight-test/clone-preflight.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=8960`.
- DHCP-required build preflight:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image alpine:3.23 \
    --output-dir /private/tmp/libkrun-osmode-container-preflight-net \
    --runtime auto \
    --platform linux/arm64 \
    --size-mb 256 \
    --require-apfs-output \
    --require-dhcp-client \
    --overlay-tar /private/tmp/libkrun-osmode-container-alpine/modules-overlay.tar \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz
  ```
  Result: build passed, the builder found `/sbin/udhcpc`, and the manifest
  recorded `require_dhcp_client=true`, `output_dir_apfs.is_apfs=true`, root disk
  checksum `f8287f886a36edf3e7077ddacdd261ac5059ad029f44e2e10646f63a96398ab5`,
  export `172 ms`, ext4 build `1347 ms`, total `1658 ms`.
- Non-network build command:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image alpine:3.23 \
    --output-dir /private/tmp/libkrun-osmode-container-alpine \
    --runtime auto \
    --platform linux/arm64 \
    --size-mb 256 \
    --pull \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz
  ```
- Non-network manifest:
  - Path: `/private/tmp/libkrun-osmode-container-alpine/manifest.json`
  - Root disk:
    `/private/tmp/libkrun-osmode-container-alpine/root.raw`
  - Root disk checksum:
    `f5d74268d486345faf5b5011f2f6d4be8c6c42499c474beeb0705d65cc713caa`
  - Rootfs tar checksum:
    `70b2cb90ec46fd287675defd986b7e19387dcda201197204c906142c83c4f8df`
  - Timings: export `178 ms`, ext4 build `1237 ms`, total `1555 ms`.
- Non-network APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-container-alpine/root.raw \
    /private/tmp/libkrun-osmode-container-alpine/vm-root.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=8640`.
- Non-network libkrun/HVF command:
  ```sh
  examples/os_mode_perf.py --timeout 30 --label container-alpine-apfs \
    --output /private/tmp/libkrun-osmode-container-alpine/perf-container-alpine.json \
    --shutdown-command 'poweroff -f' -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-container-alpine/vm-root.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0
  ```
- Non-network result:
  ```json
  {
    "exit_code": 0,
    "elapsed_ms": 1047,
    "ready_ms": 1043
  }
  ```
- Non-network readiness markers:
  ```text
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 ro,relatime
  KRUN_OSMODE: pid1=init /bin/busybox
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: network=skipped
  KRUN_OSMODE: ready
  ```
- Network overlay:
  - Alpine's container rootfs did not include the matching kernel modules
    needed for DHCP over virtio-net. The first network boot reached init but
    printed `udhcpc: socket(AF_PACKET,2,8): Address family not supported by
    protocol` and `KRUN_OSMODE: network=down`.
  - The passing network image used `--overlay-tar` with `/lib/modules` copied
    from the matching Alpine `modloop-virt` root used by the validated kernel.
  - Overlay checksum:
    `6c4f40cb9cbe8267fc445368ba66f0fa21149ad5748773607a6cb64f409c6ac7`
- Network build command:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image alpine:3.23 \
    --output-dir /private/tmp/libkrun-osmode-container-alpine-net \
    --runtime auto \
    --platform linux/arm64 \
    --size-mb 256 \
    --overlay-tar /private/tmp/libkrun-osmode-container-alpine/modules-overlay.tar \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz
  ```
- Network manifest:
  - Path: `/private/tmp/libkrun-osmode-container-alpine-net/manifest.json`
  - Root disk:
    `/private/tmp/libkrun-osmode-container-alpine-net/root.raw`
  - Root disk checksum:
    `24619b9bf76fe5c0a3cd377201c9066c43c06686b38820595b88e7c5f0a369f4`
  - Rootfs tar checksum:
    `bd2f0646788713c318f0ae7e37ca9c8af17211010928ae21e572ecd4597f4814`
  - Timings: export `168 ms`, ext4 build `1683 ms`, total `1998 ms`.
- Network APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-container-alpine-net/root.raw \
    /private/tmp/libkrun-osmode-container-alpine-net/vm-root-net.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=8960`.
- Network libkrun/HVF command:
  ```sh
  examples/os_mode_perf.py --timeout 45 --label container-alpine-overlay-gvproxy \
    --output /private/tmp/libkrun-osmode-container-alpine-net/perf-container-alpine-overlay-gvproxy.json \
    --shutdown-command 'poweroff -f' -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-container-alpine-net/vm-root-net.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0 \
      --kernel-cmdline KRUN_OSMODE_NET=1 \
      --gvproxy-socket /private/tmp/libkrun-osmode-container-alpine-net/gvproxy-container-net.sock
  ```
- Network result:
  ```json
  {
    "exit_code": 0,
    "elapsed_ms": 500,
    "ready_ms": 496
  }
  ```
- Network readiness markers:
  ```text
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 ro,relatime
  KRUN_OSMODE: pid1=init /bin/busybox
  KRUN_OSMODE: console=ttyAMA0
  udhcpc: lease of 192.168.127.2 obtained from 192.168.127.1
  KRUN_OSMODE: network=up
  KRUN_OSMODE: ready
  reboot: Power down
  ```
- Note: the root filesystem is currently mounted read-only in this smoke path.
  DHCP still succeeded, but `udhcpc` warned when updating resolver files. Future
  builder or launch tooling should make read-only versus read-write root policy
  explicit when DNS configuration persistence matters.

## Container-Derived Debian systemd Root Disk on macOS

- Status: passed for Debian `bookworm` systemd boot on macOS/ARM64 HVF without
  networking. systemd PID 1, read-write root remount, serial readiness markers,
  APFS clone boot, and poweroff exit are validated.
- Source image recipe:
  `ci/os_mode_debian_systemd.Containerfile`
- Source image build command:
  ```sh
  docker build --platform linux/arm64 \
    -f ci/os_mode_debian_systemd.Containerfile \
    -t libkrun-osmode-debian-systemd:bookworm-arm64 .
  ```
- Source image result:
  - Image: `libkrun-osmode-debian-systemd:bookworm-arm64`
  - Digest:
    `libkrun-osmode-debian-systemd@sha256:85e70e55327bcf7142502980ed91125b0694af86c5b5551c92aaddb7adb7e6cc`
  - Image ID:
    `sha256:85e70e55327bcf7142502980ed91125b0694af86c5b5551c92aaddb7adb7e6cc`
  - Size: `47014120` bytes
- Root disk build command:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image libkrun-osmode-debian-systemd:bookworm-arm64 \
    --output-dir /private/tmp/libkrun-osmode-debian-systemd \
    --runtime auto \
    --platform linux/arm64 \
    --size-mb 1024 \
    --require-apfs-output \
    --require-dhcp-client \
    --init-mode systemd \
    --overlay-tar /private/tmp/libkrun-osmode-container-alpine/modules-overlay.tar \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz
  ```
- Root disk manifest:
  - Path: `/private/tmp/libkrun-osmode-debian-systemd/manifest.json`
  - Root disk: `/private/tmp/libkrun-osmode-debian-systemd/root.raw`
  - Root disk checksum:
    `44d82fcb35157f43314f094655d4fd53f86553c862f9e0c2e9ba07f9352d721f`
  - Rootfs tar checksum:
    `6d9f840e4d722493b6a3b26dec09ff6532f63738727484276496848c935a8317`
  - Overlay checksum:
    `6c4f40cb9cbe8267fc445368ba66f0fa21149ad5748773607a6cb64f409c6ac7`
  - Output APFS check: `filesystem=apfs`, device `/dev/disk3s5`,
    mount point `/System/Volumes/Data`.
  - Timings: export `1291 ms`, ext4 build `2585 ms`, total `4346 ms`.
- systemd adaptation details:
  - Validated `/sbin/init` resolves to systemd inside the rootfs.
  - Installed `krun-osmode-ready.service` into `multi-user.target`.
  - Enabled `serial-getty@ttyAMA0.service`.
  - Added `/etc/modules-load.d/krun-osmode.conf` for
    `failover`, `net_failover`, `af_packet`, and `virtio_net`.
  - Masked `systemd-logind.service`, `apt-daily.timer`,
    `apt-daily-upgrade.timer`, `dpkg-db-backup.timer`, and
    `e2scrub_all.timer` for the constrained smoke profile.
  - The readiness service remounts `/` read-write before printing markers.
- APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-debian-systemd/root.raw \
    /private/tmp/libkrun-osmode-debian-systemd/vm-root-systemd-3.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=142704`.
- libkrun/HVF boot command:
  ```sh
  examples/os_mode_perf.py --timeout 120 --label debian-systemd-apfs \
    --output /private/tmp/libkrun-osmode-debian-systemd/perf-debian-systemd.json \
    --shutdown-command true \
    --wait-exit-after-ready 70 -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-debian-systemd/vm-root-systemd-3.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0 \
      --kernel-cmdline 'rw systemd.unit=multi-user.target KRUN_OSMODE_POWEROFF=1'
  ```
- libkrun/HVF result:
  ```json
  {
    "exit_code": 0,
    "elapsed_ms": 712,
    "ready_ms": 606
  }
  ```
- Readiness markers:
  ```text
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 rw,relatime
  KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: network=skipped
  KRUN_OSMODE: ready
  ```
- Timing details:
  - First kernel log: `78 ms`
  - Root mount: `434 ms`
  - Init start: `603 ms`
  - Ready: `606 ms`
- Notes:
  - The kernel and initramfs are the known-good Alpine aarch64 virt artifacts
    by design; the Debian container image supplies the root userspace.
  - The validation poweroff path uses `KRUN_OSMODE_POWEROFF=1`, which asks
    systemd to power off after the readiness marker.
  - This boot intentionally records `network=skipped`; Debian systemd
    networking is validated separately below.

## Container-Derived Debian systemd Root Disk with macOS gvproxy

- Date: 2026-05-16
- Host: macOS/ARM64 HVF.
- Source image:
  `libkrun-osmode-debian-systemd@sha256:de7f098a60e5de093cc9ffa3e8a9159100bd5e56809f1926a66686901bca40f2`.
- Root disk manifest:
  - Path: `/private/tmp/libkrun-osmode-debian-systemd/manifest.json`
  - Root disk checksum:
    `e102c23246e5e15c18d667077b2a8a226adf37f33eb8fc4e64e86370e7c0a142`
  - Rootfs tar checksum:
    `d8cbd62d11dc682aaaf803c645af4c779ab4c3a15be6d812ffd33d5fef95be9c`
  - Timings: export `1265 ms`, ext4 build `2612 ms`, total `4339 ms`.
- APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-debian-systemd/root.raw \
    /private/tmp/libkrun-osmode-debian-systemd/vm-root-systemd-net-6.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=143600`.
- libkrun/HVF boot command:
  ```sh
  examples/os_mode_perf.py --timeout 120 --label debian-systemd-gvproxy \
    --output /private/tmp/libkrun-osmode-debian-systemd/perf-debian-systemd-gvproxy.json \
    --shutdown-command true \
    --wait-exit-after-ready 70 -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-debian-systemd/vm-root-systemd-net-6.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0 \
      --kernel-cmdline 'rw systemd.unit=multi-user.target KRUN_OSMODE_NET=1 KRUN_OSMODE_POWEROFF=1' \
      --gvproxy-socket /private/tmp/libkrun-osmode-debian-systemd/gvproxy-systemd-net.sock
  ```
- libkrun/HVF result:
  ```json
  {
    "exit_code": 0,
    "elapsed_ms": 776,
    "ready_ms": 675
  }
  ```
- Readiness markers:
  ```text
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 rw,relatime
  KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: ifaces=eth0,lo,
  KRUN_OSMODE: link-before-dhcp=2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
  KRUN_OSMODE: network=up
  KRUN_OSMODE: addr-after-dhcp=2: eth0 inet 192.168.127.2/24 ...
  KRUN_OSMODE: ready
  ```
- Timing details:
  - First kernel log: `81 ms`
  - Root mount: `449 ms`
  - Init start: `612 ms`
  - Ready: `675 ms`
- Networking details:
  - `gvproxy` observed DHCP discover/request packets from the guest and
    offer/ack packets from server `192.168.127.1`.
  - The guest obtained lease `192.168.127.2/24`.
  - `gvproxy` counters after the run: `698 B sent to the VM`, `1.1 kB
    received from the VM`.
- Notes:
  - Debian's ISC `dhclient` failed with `Address family not supported by
    protocol` when `AF_PACKET` was not loaded, so the Debian systemd image now
    includes `udhcpc` and the shared readiness script directly `insmod`s the
    matching `af_packet` and virtio-net module set before DHCP.
  - The network module overlay still comes from the known-good Alpine virt
    kernel module tree; a Debian-owned kernel/initramfs is a separate future
    profile, not the current macOS/HVF Debian systemd profile.

## Validation Poweroff Launcher Option

- Date: 2026-05-16
- Status: implemented and syntax-checked.
- Change:
  - Added `examples/os_mode --poweroff-after-ready`.
  - The option appends `KRUN_OSMODE_POWEROFF=1` inside the validation launcher
    instead of requiring validation commands to manually add the marker to
    `--kernel-cmdline`.
  - Production launches omit the option and do not get validation poweroff
    behavior.
- Local checks:
  ```sh
  gcc -fsyntax-only -Iinclude examples/os_mode.c
  python3 -m py_compile \
    examples/os_mode_build_container_rootfs.py \
    examples/os_mode_smoke.py \
    examples/os_mode_perf.py
  sh -n \
    examples/os_mode_apfs_clone.sh \
    examples/os_mode_apfs_validate.sh \
    ci/os_mode_linux_validate.sh
  ```
- Link check:
  - `make -C examples os_mode` did not complete on this host because
    `/opt/homebrew/lib/libkrun` is not installed in the expected location:
    `ld: library 'krun' not found`.
  - The C source passed syntax checking, but a full local relink remains gated
    on installing or exposing the libkrun dylib in the example Makefile's
    linker path.

## Configurable systemd Mask List

- Date: 2026-05-16
- Status: implemented and build-validated.
- Change:
  - Added `--systemd-mask UNIT`, repeatable, to
    `examples/os_mode_build_container_rootfs.py`.
  - Added `--no-default-systemd-masks`.
  - The previous constrained-VM mask list remains the default:
    `systemd-logind.service`, `apt-daily.timer`, `apt-daily-upgrade.timer`,
    `dpkg-db-backup.timer`, and `e2scrub_all.timer`.
  - The manifest now records `systemd_default_masks`, `systemd_masks`, and
    `systemd_effective_masks`.
- Disposable build command:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image libkrun-osmode-debian-systemd:bookworm-arm64 \
    --output-dir /private/tmp/libkrun-osmode-mask-test \
    --runtime auto \
    --platform linux/arm64 \
    --size-mb 768 \
    --init-mode systemd \
    --no-default-systemd-masks \
    --systemd-mask custom-test.service
  ```
- Result:
  - Build passed.
  - Builder environment included `USE_DEFAULT_SYSTEMD_MASKS=0` and
    `SYSTEMD_MASKS=custom-test.service`.
  - Builder log showed creation of
    `/build/rootfs/etc/systemd/system/custom-test.service -> /dev/null`.
  - Manifest recorded:
    ```json
    {
      "systemd_default_masks": false,
      "systemd_masks": ["custom-test.service"],
      "systemd_effective_masks": ["custom-test.service"]
    }
    ```
- Local checks:
  ```sh
  python3 -m py_compile \
    examples/os_mode_build_container_rootfs.py \
    examples/os_mode_smoke.py \
    examples/os_mode_perf.py
  ```

## Debian systemd Kernel/Profile Decision

- Date: 2026-05-16
- Status: decided for the current macOS/ARM64 HVF profile.
- Decision:
  - Continue using the known-good Alpine `6.18.22-0-virt` aarch64 kernel and
    matching initramfs for the Debian systemd validation profile.
  - Treat the Debian container-derived rootfs as userspace only.
  - A Debian-owned kernel/initramfs remains a future, separate image profile
    that must prove virtio-mmio block, PL011 serial, virtio-net, packet socket,
    ext4 root mount, and macOS/HVF boot behavior before replacing the current
    kernel path.
- Evidence:
  - The exported Debian systemd container rootfs contains `boot/`, but no
    bootable `vmlinuz`, `initrd`, or `initramfs` artifact.
  - The passing Debian systemd boot and networking validations used the Alpine
    kernel/initramfs plus the matching Alpine module overlay.
  - Keeping the known-good kernel avoids mixing a new guest kernel variable
    into the already-passing container-rootfs, APFS clone, systemd, and gvproxy
    validation gates.
- Local inspection:
  ```sh
  tar -tf /private/tmp/libkrun-osmode-debian-systemd/rootfs.tar \
    | rg '(^|/)vmlinuz|(^|/)initrd|(^|/)initramfs|^boot/'
  ```
  Result: only `boot/` and systemd/initramfs-tools support files were present;
  no bootable kernel or initramfs artifact was present.

## Debian systemd APFS Repeated Writes

- Date: 2026-05-16
- Status: passed for repeated macOS/ARM64 HVF boots from the same APFS clone.
- Purpose:
  - Prove a container-derived Debian systemd root disk can be APFS-cloned on
    the macOS host, booted as a full Linux OS under libkrun/HVF, and used for
    normal guest writes.
  - Prove journald and package-manager metadata writes land in the per-VM
    clone while the immutable base image remains unchanged.
- Root disk manifest:
  - Path: `/private/tmp/libkrun-osmode-debian-systemd/manifest.json`
  - Root disk: `/private/tmp/libkrun-osmode-debian-systemd/root.raw`
  - Root disk checksum:
    `547368b2d719e349de52253741e7d57bd5352e602c80d1fc2d05789d9989ee4e`
  - Rootfs tar checksum:
    `c5379136068549272da00571182537716b0ec5a8adfe0d7cc382aa03254ff77f`
  - Output APFS check: `filesystem=apfs`, device `/dev/disk3s5`,
    mount point `/System/Volumes/Data`.
  - Timings: export `1289 ms`, ext4 build `2558 ms`, total `4330 ms`.
  - systemd masks: default constrained-VM mask list.
- Base image allocated size before clone: `143600 KiB`.
- APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-debian-systemd/root.raw \
    /private/tmp/libkrun-osmode-debian-systemd/vm-root-systemd-write.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=143600`.
- Boot command, repeated twice against the same clone:
  ```sh
  examples/os_mode_perf.py --timeout 240 --label debian-systemd-apfs-write-1 \
    --output /private/tmp/libkrun-osmode-debian-systemd/perf-debian-systemd-write-1.json \
    --shutdown-command true \
    --wait-exit-after-ready 120 -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-debian-systemd/vm-root-systemd-write.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0 \
      --kernel-cmdline 'rw systemd.unit=multi-user.target KRUN_OSMODE_NET=1 KRUN_OSMODE_WRITE_TEST=1 KRUN_OSMODE_APT_UPDATE=1' \
      --poweroff-after-ready \
      --gvproxy-socket /private/tmp/libkrun-osmode-debian-systemd/gvproxy-systemd-write.sock
  ```
- First boot result:
  ```json
  {
    "elapsed_ms": 2181,
    "exit_code": 0,
    "ready_ms": 2078,
    "write_ms": 722,
    "journald_ms": 726,
    "package_manager_ms": 2078,
    "root_mount_ms": 479,
    "init_start_ms": 661,
    "first_kernel_log_ms": 94
  }
  ```
- First boot markers:
  ```text
  KRUN_OSMODE: network=up
  KRUN_OSMODE: write=ok path=/var/lib/krun-osmode/write-test/b12ba49b-c588-4b4a-bfeb-5dc7b66b8704.txt
  KRUN_OSMODE: journald=ok
  KRUN_OSMODE: package-manager=apt-update-ok lists_kib=19060
  KRUN_OSMODE: ready
  ```
- First boot storage and checksums:
  - Clone allocated size after boot: `152896 KiB`.
  - Base checksum after boot:
    `547368b2d719e349de52253741e7d57bd5352e602c80d1fc2d05789d9989ee4e`.
  - Clone checksum after boot:
    `b0bfef9590f1f623aecedc2a5623eb818748c2545ec743b5779aeb7edb415330`.
- Second boot result:
  ```json
  {
    "elapsed_ms": 2106,
    "exit_code": 0,
    "ready_ms": 1996,
    "write_ms": 676,
    "journald_ms": 679,
    "package_manager_ms": 1995,
    "root_mount_ms": 451,
    "init_start_ms": 624,
    "first_kernel_log_ms": 83
  }
  ```
- Second boot markers:
  ```text
  KRUN_OSMODE: network=up
  KRUN_OSMODE: write=ok path=/var/lib/krun-osmode/write-test/1de1bcb3-e187-4a71-abb1-98032381ddf9.txt
  KRUN_OSMODE: journald=ok
  KRUN_OSMODE: package-manager=apt-update-ok lists_kib=19060
  KRUN_OSMODE: ready
  ```
- Second boot storage and checksums:
  - Clone allocated size after boot: `153056 KiB`.
  - Base checksum after boot:
    `547368b2d719e349de52253741e7d57bd5352e602c80d1fc2d05789d9989ee4e`.
  - Clone checksum after boot:
    `d9420ef311c3f5c9ae3bf1b819bb4b8895a42f6f71c51064bbd06384ec3dc8c3`.
- gvproxy result:
  - DHCP and outbound package-manager traffic passed through gvproxy.
  - Counters after two boots were approximately `19 MB` sent to the VM and
    `438 kB` received from the VM.
- Conclusion:
  - APFS clone provisioning remains metadata-cheap at launch time.
  - Guest writes from systemd, journald, readiness probes, DHCP, and
    `apt-get update` are isolated to the per-VM clone.
  - The immutable base image checksum remained unchanged across both boots.

## Debian systemd Persistent Control Channel

- Date: 2026-05-16
- Status: passed for macOS/ARM64 HVF.
- Purpose:
  - Prove a Debian systemd OS-mode guest can boot without
    `--poweroff-after-ready`.
  - Prove the host can retain a managed serial control channel after readiness.
  - Prove a command sent through that control channel can shut the guest down
    and make libkrun exit cleanly.
- Builder change:
  - Added `examples/os_mode_build_container_rootfs.py
    --systemd-serial-control-shell`.
  - In `--init-mode systemd`, this validation-only option starts a root shell
    on `ttyAMA0` after `krun-osmode-ready.service`, masks
    `serial-getty@ttyAMA0.service`, and masks `console-getty.service` so a
    login prompt does not consume host control commands.
  - Added `examples/os_mode_perf.py --control-command`,
    `--expect-control-marker`, and `--control-delay`.
  - Fixed `examples/os_mode_perf.py` to read guest output with nonblocking
    selector polling; the previous blocking `readline()` path could miss the
    timeout when a guest printed a partial prompt with no newline.
- Disposable root disk build command:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image libkrun-osmode-debian-systemd:bookworm-arm64 \
    --output-dir /private/tmp/libkrun-osmode-control-test \
    --runtime docker \
    --platform linux/arm64 \
    --size-mb 768 \
    --init-mode systemd \
    --systemd-serial-control-shell
  ```
- Build result:
  - Source image:
    `libkrun-osmode-debian-systemd@sha256:de7f098a60e5de093cc9ffa3e8a9159100bd5e56809f1926a66686901bca40f2`
  - Root disk checksum:
    `500b9ec6b838e4efb3868bf45a1ce71b21fcfb6faa073bb3db85086dfd21ac12`
  - Rootfs tar checksum:
    `505820c009e9757332d6bffb4561f8435676e5b07480b6ac7486519f1ec09561`
  - Timings: export `1322 ms`, ext4 build `2594 ms`, total `4294 ms`.
  - Manifest recorded `systemd_serial_control_shell: true`.
- ext4 image inspection:
  ```sh
  /opt/homebrew/opt/e2fsprogs/sbin/debugfs \
    -R 'cat /etc/systemd/system/krun-osmode-serial-control.service' \
    /private/tmp/libkrun-osmode-control-test/root.raw
  ```
  Result included:
  ```ini
  [Unit]
  Description=libkrun OS-mode validation serial control shell
  After=krun-osmode-ready.service
  Conflicts=console-getty.service serial-getty@ttyAMA0.service

  [Service]
  Type=simple
  ExecStart=/bin/sh -i
  StandardInput=tty
  StandardOutput=tty
  StandardError=tty
  TTYPath=/dev/ttyAMA0
  TTYReset=yes
  TTYVHangup=no
  Restart=no
  ```
  `debugfs stat` also confirmed:
  - `multi-user.target.wants/krun-osmode-serial-control.service ->
    ../krun-osmode-serial-control.service`
  - `console-getty.service -> /dev/null`
  - `serial-getty@ttyAMA0.service -> /dev/null`
- APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-control-test/root.raw \
    /private/tmp/libkrun-osmode-control-test/vm-root-control-5.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=143024`.
- libkrun/HVF boot command:
  ```sh
  examples/os_mode_perf.py --timeout 120 \
    --label debian-systemd-persistent-control \
    --output /private/tmp/libkrun-osmode-control-test/perf-persistent-control.json \
    --control-delay 4 \
    --control-command 'p=KRUN_OSMODE; echo "$p: control=ok"; poweroff -f' \
    --expect-control-marker 'KRUN_OSMODE: control=ok' \
    --wait-exit-after-ready 30 -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-control-test/vm-root-control-5.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0 \
      --kernel-cmdline 'rw systemd.unit=multi-user.target'
  ```
- libkrun/HVF result:
  ```json
  {
    "elapsed_ms": 4730,
    "exit_code": 0,
    "timings": {
      "first_kernel_log_ms": 86,
      "root_mount_ms": 462,
      "init_start_ms": 637,
      "ready_ms": 643,
      "control_ms": 4676
    }
  }
  ```
- Markers:
  ```text
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 rw,relatime
  KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: network=skipped
  KRUN_OSMODE: ready
  KRUN_OSMODE: control=ok
  ```
- Storage and checksums:
  - Base allocated size: `143024 KiB`.
  - Clone allocated size after boot/control/poweroff: `143216 KiB`.
  - Base checksum:
    `500b9ec6b838e4efb3868bf45a1ce71b21fcfb6faa073bb3db85086dfd21ac12`.
  - Clone checksum after boot:
    `6b14a144fc72f5e98e2d88326d44cbc4d59b9daba91558454a9252264a4dd41f`.
- Notes:
  - A prior attempt using `systemctl --no-block poweroff` from the control
    shell printed the control marker but did not make libkrun exit within the
    wait window. The validated control shutdown command is `poweroff -f`.
  - A prior control-shell image did not mask `console-getty.service`; the
    console login prompt consumed the host command. The passing image masks
    both console and serial getty units for this validation-only mode.

## Debian systemd Larger-Root APFS Storage-Growth Baseline

- Date: 2026-05-16
- Status: passed for macOS/ARM64 HVF.
- Purpose:
  - Establish an APFS allocated-size baseline for a larger sparse Debian
    systemd root image.
  - Prove representative guest writes still affect only the per-VM clone.
  - Representative writes include DHCP state, journald write/readback, a
    readiness marker file, and `apt-get update` package-manager metadata.
- Root disk build command:
  ```sh
  examples/os_mode_build_container_rootfs.py \
    --image libkrun-osmode-debian-systemd:bookworm-arm64 \
    --output-dir /private/tmp/libkrun-osmode-large-root \
    --runtime docker \
    --platform linux/arm64 \
    --size-mb 4096 \
    --require-apfs-output \
    --require-dhcp-client \
    --init-mode systemd \
    --overlay-tar /private/tmp/libkrun-osmode-container-alpine/modules-overlay.tar \
    --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
    --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz
  ```
- Build result:
  - Source image:
    `libkrun-osmode-debian-systemd@sha256:de7f098a60e5de093cc9ffa3e8a9159100bd5e56809f1926a66686901bca40f2`
  - Output filesystem: APFS on `/dev/disk3s5`.
  - Apparent root disk size: `4096 MiB`.
  - Root disk allocated size before clone: `146016 KiB`.
  - Root disk checksum:
    `990e0af58657db056cafdc9a252e2654123fbcd783f37e67e4fd04b3092d9d3b`
  - Rootfs tar checksum:
    `ea57c702e0cfac232ee3ff77e8a1370e74bf68b29cc268b77ddd423d06902799`
  - Overlay checksum:
    `6c4f40cb9cbe8267fc445368ba66f0fa21149ad5748773607a6cb64f409c6ac7`
  - Timings: export `1342 ms`, ext4 build `12338 ms`, total `15370 ms`.
- APFS clone command:
  ```sh
  examples/os_mode_apfs_clone.sh \
    /private/tmp/libkrun-osmode-large-root/root.raw \
    /private/tmp/libkrun-osmode-large-root/vm-root-large-write.raw
  ```
  Result: `mode=clone`, `elapsed_ms=0`, `allocated_kib=146016`.
- gvproxy command:
  ```sh
  /opt/homebrew/Cellar/podman/5.8.2/libexec/podman/gvproxy \
    --debug \
    --listen-vfkit unixgram:///private/tmp/libkrun-osmode-large-root/gvproxy-large-write.sock \
    --services unix:///private/tmp/libkrun-osmode-large-root/gvproxy-large-write-services.sock \
    --ssh-port 2228 \
    --pcap /private/tmp/libkrun-osmode-large-root/gvproxy-large-write.pcap
  ```
- libkrun/HVF boot command:
  ```sh
  examples/os_mode_perf.py --timeout 240 \
    --label debian-systemd-large-root-write \
    --output /private/tmp/libkrun-osmode-large-root/perf-large-root-write.json \
    --shutdown-command true \
    --wait-exit-after-ready 120 -- \
    examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-large-root/vm-root-large-write.raw \
      --root-device /dev/vda \
      --root-fstype ext4 \
      --guest-init /sbin/init \
      --console ttyAMA0 \
      --kernel-cmdline 'rw systemd.unit=multi-user.target KRUN_OSMODE_NET=1 KRUN_OSMODE_WRITE_TEST=1 KRUN_OSMODE_APT_UPDATE=1' \
      --poweroff-after-ready \
      --gvproxy-socket /private/tmp/libkrun-osmode-large-root/gvproxy-large-write.sock
  ```
- libkrun/HVF result:
  ```json
  {
    "elapsed_ms": 2633,
    "exit_code": 0,
    "timings": {
      "first_kernel_log_ms": 276,
      "root_mount_ms": 695,
      "init_start_ms": 901,
      "write_ms": 993,
      "journald_ms": 997,
      "package_manager_ms": 2527,
      "ready_ms": 2528
    }
  }
  ```
- Markers:
  ```text
  KRUN_OSMODE: init-started
  KRUN_OSMODE: root=/dev/vda ext4 rw,relatime
  KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd
  KRUN_OSMODE: console=ttyAMA0
  KRUN_OSMODE: network=up
  KRUN_OSMODE: write=ok path=/var/lib/krun-osmode/write-test/598f2e99-d394-4f57-8718-b66dc0a2ff98.txt
  KRUN_OSMODE: journald=ok
  KRUN_OSMODE: package-manager=apt-update-ok lists_kib=19060
  KRUN_OSMODE: ready
  ```
- Storage and checksums:
  - Base allocated size before and after boot: `146016 KiB`.
  - Clone allocated size before boot: `146016 KiB`.
  - Clone allocated size after representative writes: `155328 KiB`.
  - Allocated-size growth in the clone: `9312 KiB`.
  - Base checksum after boot:
    `990e0af58657db056cafdc9a252e2654123fbcd783f37e67e4fd04b3092d9d3b`.
  - Clone checksum after boot:
    `d36745b4b95d2c139072e0b67f290706c1cb1753265ba9fca96301ccaa083037`.
- gvproxy result:
  - DHCP succeeded with lease `192.168.127.2/24`.
  - `apt-get update` fetched Debian package metadata over gvproxy.
  - Final gvproxy counters were approximately `9.7 MB` sent to the VM and
    `199 kB` received from the VM.
- Conclusion:
  - A 4 GiB sparse Debian systemd root image remains metadata-cheap to APFS
    clone for launch.
  - Representative writes increased the per-VM clone allocation by about
    `9.1 MiB`.
  - The immutable base image checksum remained unchanged.

## Known-Good Guest Artifacts

- macOS/ARM64 HVF:
  - Kernel: Alpine Linux `6.18.22-0-virt` aarch64.
  - Kernel format: `KRUN_KERNEL_FORMAT_RAW` / `2`.
  - Initramfs: `initramfs-virt-with-ext4.gz`, custom merge of Alpine
    `initramfs-virt` plus `modloop-virt` modules.
  - Root: Alpine `3.23.4` aarch64 minirootfs ext4 image.
  - Console: `ttyAMA0`.
  - Root device used in smoke tests: whole-disk `/dev/vda`.
- Linux/KVM: deferred until a real Linux host or Linux CI runner with
  `/dev/kvm` is available.

## Networking

- Status: macOS gvproxy runtime passed for Alpine and Debian systemd guests
  with gvproxy v0.8.8 and no legacy `VFKT` magic.
- Linux passt command: deferred until Linux host.
- Linux guest result: deferred until Linux host.
- macOS gvproxy/vmnet-helper command:
  - Podman installed `gvproxy` at
    `/opt/homebrew/Cellar/podman/5.8.2/libexec/podman/gvproxy`.
  - Passing the raw socket path without escalation failed in libkrun with
    `Binding(EPERM)`, so macOS networking smoke must run outside the sandbox.
  - Escalated gvproxy command:
    ```sh
    /opt/homebrew/Cellar/podman/5.8.2/libexec/podman/gvproxy \
      --debug \
      --listen-vfkit unixgram:///private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/gvproxy-vfkit-v088-nomagic2.sock \
      --services unix:///private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/gvproxy-services-v088-nomagic2.sock \
      --ssh-port 2225 \
      --pcap /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/gvproxy-v088-nomagic2.pcap
    ```
  - Escalated libkrun command included:
    ```sh
    examples/os_mode_perf.py --timeout 60 --label gvproxy-v088-nomagic2 \
      --output /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/perf-gvproxy-nomagic2.json \
      --shutdown-command 'poweroff -f' -- \
      examples/os_mode \
      --kernel /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/vmlinuz-virt \
      --initramfs /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/initramfs-virt-with-ext4.gz \
      --root-disk /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/rootfs-net-nomagic2.ext4 \
      --root-device /dev/vda \
      --kernel-cmdline modules=ext4 \
      --guest-init /sbin/init \
      --gvproxy-socket /private/tmp/libkrun-osmode-artifacts/alpine-3.23.4-aarch64/gvproxy-vfkit-v088-nomagic2.sock
    ```
- macOS guest result:
  - libkrun unixgram binding succeeded outside the sandbox.
  - gvproxy v0.8.8 saw the vfkit client connection without the legacy `VFKT`
    magic. A prior attempt with `NET_FLAG_VFKIT` connected but did not pass
    traffic, so current gvproxy smoke tests should not send that magic unless
    validating an older helper that requires it.
  - The guest loaded `AF_PACKET`, loaded `virtio_net`, and observed
    `KRUN_OSMODE: ifaces=eth0,lo,`.
  - DHCP succeeded: lease `192.168.127.2` from server `192.168.127.1`.
  - Gateway ping succeeded: one packet to `192.168.127.1`, `0%` packet loss.
  - Last markers: `KRUN_OSMODE: network=up`, then `KRUN_OSMODE: ready`.
  - gvproxy counters after the run: `838 B sent to the VM`, `914 B received
    from the VM`.
  - Conclusion: `krun_add_net_unixgram()` works for OS-mode guests on
    macOS/ARM64 HVF with gvproxy v0.8.8 when the legacy `VFKT` datagram is not
    sent. The Debian systemd validation additionally proves the same path
    after PID 1 is systemd.

## OCI OS Bundle Pull-to-Launch on macOS

- Status: passed for local Docker image reference on macOS/ARM64 HVF.
- Goal:
  - Prove the macOS host can consume a container image that already contains a
    complete `libkrun.os-bundle.v1` payload, extract `root.raw` and kernel
    artifacts without rebuilding the root disk, APFS-clone the extracted
    immutable root, and boot Debian systemd under libkrun/HVF from the host
    process.
- Build dependencies installed during validation:
  - `brew install llvm`
  - `brew install lld`
  - Rebuild command:
    `PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang`
- Source artifact manifest:
  - `/private/tmp/libkrun-osmode-debian-systemd-current/manifest.json`
  - Source image: `libkrun-osmode-debian-systemd:bookworm-arm64`
  - Source digest:
    `libkrun-osmode-debian-systemd@sha256:de7f098a60e5de093cc9ffa3e8a9159100bd5e56809f1926a66686901bca40f2`
  - Platform: `linux/arm64`
  - Root disk SHA-256:
    `cf07d9a0cdb84f505b529ea72494c760fabb5c1fd8a400c569eef314a5590971`
- Published bundle image:
  - Command:
    `examples/os_mode_publish_container_bundle.py /private/tmp/libkrun-osmode-debian-systemd-current/manifest.json --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-context-current --image-tag libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --runtime docker`
  - Result: Docker image
    `libkrun-osmode-debian-systemd-bundle:bookworm-arm64` built successfully.
  - Bundle context:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-context-current`
- Import-only validation:
  - Command:
    `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-current3 --runtime docker --clone-dest vm-root.raw --smoke-output smoke.json --perf-output perf.json`
  - Result: passed. The importer extracted `/libkrun-os-bundle`, verified
    manifest/digests, and printed APFS clone, host launch, smoke, and perf
    commands.
- Host/HVF smoke validation from extracted bundle:
  - Successful command:
    `examples/os_mode_import_container_bundle.py --bundle-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-current3/libkrun-os-bundle --clone-dest vm-root-run-4.raw --smoke-output smoke-run-4.json --perf-output perf-run-4.json --run`
  - Smoke evidence:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-current3/libkrun-os-bundle/smoke-run-4.json`
  - Result: `ready=true`, `exit_code=0`, `failure_reason=null`, PID 1
    `systemd /usr/lib/systemd/systemd`, root `/dev/vda ext4 rw,relatime`,
    console `ttyAMA0`, network marker `network=skipped`, and clean shutdown to
    `reboot: Power down`.
- End-to-end image import plus host/HVF smoke validation:
  - Command:
    `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-run-image1 --runtime docker --clone-dest vm-root-run-image1.raw --smoke-output smoke-run-image1.json --perf-output perf-run-image1.json --run`
  - Smoke evidence:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-run-image1/libkrun-os-bundle/smoke-run-image1.json`
  - Result: `ready=true`, `exit_code=0`, `failure_reason=null`,
    `imported_image=libkrun-osmode-debian-systemd-bundle:bookworm-arm64`.
  - Timings from this run used the earlier evidence schema where
    `importer_total` meant post-extraction runtime: bundle extraction
    `10128 ms`, APFS clone `178 ms`, smoke `1477 ms`, post-extraction run
    total `1656 ms`.
  - VMM child PID is recorded as a child of the smoke launcher process, not
    Docker/Podman.
- Perf evidence:
  - APFS clone:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-run-image1/libkrun-os-bundle/vm-root-perf-image1.raw`
  - Perf evidence:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-run-image1/libkrun-os-bundle/perf-run-image1.json`
  - Timings: first kernel log `140 ms`, root marker `1196 ms`, PID 1 marker
    `1199 ms`, console marker `1201 ms`, ready marker `1205 ms`, elapsed
    `1209 ms`.
- Immutable root verification:
  - Before/after SHA-256 for extracted immutable `root.raw`:
    `cf07d9a0cdb84f505b529ea72494c760fabb5c1fd8a400c569eef314a5590971`.
  - Guest writes landed in APFS clones, not the extracted bundle root.
- Repeated clone validation:
  - The same extracted bundle directory booted through multiple fresh clone
    destinations (`vm-root-run-2.raw`, `vm-root-run-3.raw`,
    `vm-root-run-4.raw`) without re-exporting the image or rebuilding
    `root.raw`. Earlier runs exposed helper issues; the final run passed after
    the smoke drain fix.
- Fixes made during runtime validation:
  - Publisher normalizes whole-number float smoke timeout values from current
    source manifests into integer bundle-manifest fields.
  - Importer creates scratch bundle containers with a placeholder command
    (`docker create IMAGE true`) so Docker can copy from images with no default
    command.
  - Importer treats `root_disk_allocated_bytes` as typed provenance, not a
    portable exact invariant after Docker/Podman extraction.
  - Importer supports `--reuse-extracted-output-dir` for explicit cached
    imports. Reuse is accepted only when the existing output directory contains
    `libkrun-os-bundle/` and import metadata whose `image_reference` matches the
    requested image.
  - Real cache validation:
    `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1 --runtime docker --clone-dest vm-root-cache1.raw --smoke-output smoke-cache1.json --perf-output perf-cache1.json`
    created
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/.libkrun-os-bundle-import.json`.
    A second run with `--reuse-extracted-output-dir` and clone destination
    `vm-root-cache2.raw` succeeded without Docker access and printed commands
    against the cached `libkrun-os-bundle/`.
  - Runtime cache-reuse validation with current timing schema:
    `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1 --reuse-extracted-output-dir --clone-dest vm-root-cache-run1.raw --smoke-output smoke-cache-run1.json --run`
    succeeded without invoking Docker/Podman extraction.
  - Runtime cache-reuse smoke evidence:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/smoke-cache-run1.json`
  - Result: `ready=true`, `exit_code=0`, `failure_reason=null`,
    `bundle_extraction_reused=true`, `imported_image=libkrun-osmode-debian-systemd-bundle:bookworm-arm64`,
    `expected_pid1=systemd`, `expected_root=/dev/vda`,
    `expected_console=ttyAMA0`, launcher PID `55667`, child VMM PID `55668`.
    Observed markers included `KRUN_OSMODE: init-started`,
    `KRUN_OSMODE: root=`, `KRUN_OSMODE: pid1=`,
    `KRUN_OSMODE: console=`, and `KRUN_OSMODE: ready`; the run powered off
    cleanly.
  - Current timing-schema values: bundle extraction `0 ms`, APFS clone
    `88 ms`, smoke `754 ms`, post-extraction run `842 ms`, true importer total
    `1276 ms`.
  - Structured-observed-value cache-reuse validation:
    `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1 --reuse-extracted-output-dir --clone-dest vm-root-cache-run2.raw --smoke-output smoke-cache-run2.json --run`
    succeeded with smoke evidence at
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/smoke-cache-run2.json`.
    Result: `ready=true`, `exit_code=0`, `failure_reason=null`,
    `bundle_extraction_reused=true`, `observed_root=/dev/vda`,
    `observed_root_line="/dev/vda ext4 rw,relatime"`,
    `observed_pid1=systemd`,
    `observed_pid1_line="systemd /usr/lib/systemd/systemd"`,
    `observed_console=ttyAMA0`, `observed_consoles=["ttyAMA0"]`, and
    `observed_network=skipped`. Timings: bundle extraction `0 ms`, APFS clone
    `80 ms`, smoke `773 ms`, post-extraction run `853 ms`, true importer total
    `1282 ms`.
  - Structured-observed-value perf validation:
    `examples/os_mode_apfs_clone.sh /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/root.raw /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/vm-root-perf-observed1.raw`
    followed by
    `examples/os_mode_perf.py --timeout 30 --label cached-bundle-observed --output /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/perf-observed1.json --require-pid1-marker --expect-root /dev/vda --expect-console ttyAMA0 -- examples/os_mode ...`
    succeeded.
  - Perf evidence:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/perf-observed1.json`
  - Result: `failure_reason=null`, `observed_root=/dev/vda`,
    `observed_root_line="/dev/vda ext4 rw,relatime"`,
    `observed_pid1=systemd`,
    `observed_pid1_line="systemd /usr/lib/systemd/systemd"`,
    `observed_console=ttyAMA0`, `observed_consoles=["ttyAMA0"]`, and
    `observed_network=skipped`. Timings: first kernel log `73 ms`, root marker
    `589 ms`, PID 1 marker `592 ms`, console marker `592 ms`, ready marker
    `594 ms`.
  - Runtime validation after bundle enrichment hardening:
    `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1 --reuse-extracted-output-dir --clone-dest vm-root-cache-run3.raw --smoke-output smoke-cache-run3.json --run`
    succeeded with the importer checking structured observed root, console, and
    PID 1 before writing bundle metadata.
  - Smoke evidence:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/smoke-cache-run3.json`
  - Result: `ready=true`, `exit_code=0`, `failure_reason=null`,
    `bundle_extraction_reused=true`, `observed_root=/dev/vda`,
    `observed_pid1=systemd`, `observed_console=ttyAMA0`, and
    `observed_network=skipped`. Timings: bundle extraction `0 ms`, APFS clone
    `172 ms`, smoke `1975 ms`, post-extraction run `2148 ms`, true importer
    total `2875 ms`.
  - macOS epoll shim returns `io::Error` instead of aborting when `kevent`
    cannot register redirected serial stdin.
  - Smoke and perf helpers detect `KRUN_OSMODE:` markers embedded in
    kernel/journald-prefixed serial lines.
  - Smoke helper keeps draining stdout after readiness while waiting for clean
    VMM exit, preventing serial pipe backpressure from stalling guest shutdown.

## Performance

- Status: macOS/ARM64 HVF OS-mode BusyBox, Debian systemd, and Debian
  systemd-with-gvproxy baselines recorded.
- Workload-mode baseline: not recorded; existing workload examples require a
  prepared virtiofs root and libkrun workload kernel path.
- OS-mode BusyBox boot:
  - APFS clone 1: ready `458 ms`, root mount `447 ms`, init start `457 ms`,
    first kernel log `77 ms`, elapsed `461 ms`.
  - APFS clone 2: ready `452 ms`, root mount `441 ms`, init start `451 ms`,
    first kernel log `75 ms`, elapsed `455 ms`.
  - APFS clone 3: ready `438 ms`, root mount `427 ms`, init start `437 ms`,
    first kernel log `73 ms`, elapsed `441 ms`.
- OS-mode Debian systemd boot:
  - APFS clone: ready `606 ms`, root mount `434 ms`, init start `603 ms`,
    first kernel log `78 ms`, elapsed `712 ms`.
  - APFS clone with gvproxy: ready `675 ms`, root mount `449 ms`, init start
    `612 ms`, first kernel log `81 ms`, elapsed `776 ms`.
  - APFS clone with gvproxy, journald write, and `apt-get update`, first boot:
    ready `2078 ms`, root mount `479 ms`, init start `661 ms`,
    first kernel log `94 ms`, elapsed `2181 ms`.
  - Same APFS clone with gvproxy, journald write, and `apt-get update`, second
    boot: ready `1996 ms`, root mount `451 ms`, init start `624 ms`,
    first kernel log `83 ms`, elapsed `2106 ms`.
  - APFS clone with validation serial control shell, no readiness auto-poweroff:
    ready `643 ms`, root mount `462 ms`, init start `637 ms`,
    first kernel log `86 ms`, serial control marker `4676 ms`, elapsed
    `4730 ms`, exit code `0`.
  - 4 GiB APFS clone with gvproxy, journald write, and `apt-get update`:
    ready `2528 ms`, root mount `695 ms`, init start `901 ms`,
    first kernel log `276 ms`, elapsed `2633 ms`, exit code `0`.
  - OCI bundle image import plus APFS clone plus clean-shutdown smoke, recorded
    before the importer timing schema split total and post-extraction runtime:
    bundle extraction `10128 ms`, APFS clone `178 ms`, smoke `1477 ms`,
    post-extraction run total `1656 ms`, exit code `0`.
  - OCI bundle perf clone: ready `1205 ms`, root marker `1196 ms`, PID 1
    marker `1199 ms`, console marker `1201 ms`, first kernel log `140 ms`,
    elapsed `1209 ms`.
  - OCI bundle cache-reuse clean-shutdown smoke with current timing schema:
    bundle extraction `0 ms`, APFS clone `88 ms`, smoke `754 ms`,
    post-extraction run `842 ms`, true importer total `1276 ms`, exit code
    `0`.
  - OCI bundle cache-reuse smoke with structured observed markers: bundle
    extraction `0 ms`, APFS clone `80 ms`, smoke `773 ms`, post-extraction run
    `853 ms`, true importer total `1282 ms`, exit code `0`, observed root
    `/dev/vda`, observed PID 1 `systemd`, observed console `ttyAMA0`.
  - OCI bundle perf with structured observed markers: first kernel log
    `73 ms`, root marker `589 ms`, PID 1 marker `592 ms`, console marker
    `592 ms`, ready marker `594 ms`, observed root `/dev/vda`, observed PID 1
    `systemd`, observed console `ttyAMA0`.
  - OCI bundle cache-reuse smoke after enrichment hardening: bundle extraction
    `0 ms`, APFS clone `172 ms`, smoke `1975 ms`, post-extraction run
    `2148 ms`, true importer total `2875 ms`, exit code `0`, observed root
    `/dev/vda`, observed PID 1 `systemd`, observed console `ttyAMA0`.
- Time to first kernel log: `73-77 ms` in the three APFS clone runs.
- Time to root mount: `427-447 ms` in the three APFS clone runs.
- Time to init start: `437-457 ms` in the three APFS clone runs.
- Time to ready: `438-458 ms` in the three BusyBox APFS clone runs; `606 ms`
  in the Debian systemd APFS clone run; `675 ms` in the Debian systemd
  gvproxy run; `1205 ms` in the OCI bundle perf run using the same Debian
  systemd userspace and Alpine virt kernel/initramfs profile.
- APFS clone creation: earlier runs reported `0 ms` because the helper used a
  one-second timestamp floor. The helper now uses monotonic millisecond timing
  when `python3` is available; each earlier smoke clone reported
  `allocated_kib=82080`, and the Debian systemd gvproxy clone reported
  `allocated_kib=143600`.
- APFS clone allocated-size growth during Debian repeated-write validation:
  `143600 KiB` at clone creation, `152896 KiB` after the first systemd,
  journald, and `apt-get update` boot, and `153056 KiB` after the second boot.
- Larger-root APFS clone allocated-size growth: a 4 GiB sparse Debian systemd
  root image reported `146016 KiB` allocated at clone creation and `155328 KiB`
  after DHCP, journald write/readback, readiness marker write, and
  `apt-get update`.
- Full-copy baseline: `0 ms` at one-second timestamp resolution for the tiny
  host-side 16 MiB validation file; not representative for large roots.
- Direct kernel boot without initramfs:
  - Command omitted `--initramfs`.
  - Result: host process aborted before guest markers, exit code `-6`.
  - Conclusion: with the current Alpine virt artifact, initramfs remains
    required. A future comparison needs a guest kernel with ext4 and virtio-blk
    built in.
- Optimization decision from current data: prioritize guest image/kernel
  composition and initramfs removal before VMM setup. APFS clone setup is already
  below the helper's current timing resolution for these images. Guest boot to
  readiness is roughly `0.44-0.46 s` for BusyBox, `0.61 s` for the first Debian
  systemd profile, `0.68 s` with Debian systemd networking, and about `2.0-2.1 s`
  when Debian systemd also performs journald readback plus `apt-get update`.

### 2026-05-18: Cached Bundle Repeat-Launch Baseline

- Command:
  `examples/os_mode_import_container_bundle.py --image libkrun-osmode-debian-systemd-bundle:bookworm-arm64 --output-dir /private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1 --reuse-extracted-output-dir --clone-dest vm-root-repeat-baseline1.raw --smoke-output smoke-repeat-baseline1.json --run`
- Evidence:
  `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/smoke-repeat-baseline1.json`
- Result: passed.
- No stale host processes remained after the run:
  `pgrep -fl os_mode` and `pgrep -fl gvproxy` returned no matches.
- Observed markers:
  - `ready=true`
  - `failure_reason=null`
  - `observed_root=/dev/vda`
  - `observed_pid1=systemd`
  - `observed_console=ttyAMA0`
  - `observed_network=skipped`
- Bundle/importer evidence:
  - `bundle_extraction_reused=true`
  - `bundle_extraction=0 ms`
  - `apfs_clone=74 ms`
  - `smoke=751 ms`
  - `post_extraction_run=827 ms`
  - `importer_total=1283 ms`
  - clone:
    `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-cache1/libkrun-os-bundle/vm-root-repeat-baseline1.raw`
- Conclusion: the same extracted Debian systemd bundle cache can start another
  VM without Docker/Podman extraction. The repeat launch used only APFS clone
  creation plus host-side libkrun/HVF boot and smoke validation.

### 2026-05-18: Product Baseline Table Tooling

- Added explicit importer pull timing:
  `examples/os_mode_import_container_bundle.py --pull` records
  `bundle.timings_ms.image_pull` in smoke evidence when a bundle image is
  pulled before extraction. `examples/krun_os_run.py --pull` forwards the same
  flag for the product-facing path.
- Added `examples/os_mode_baseline_table.py`, which renders release evidence
  archives or direct smoke/perf JSON as a Markdown baseline table with columns
  for image pull/export, bundle extraction, APFS clone, first output, root
  marker, PID 1 marker, ready marker, clean poweroff, and total time.
- Validation:
  `make os-mode-checks` passed on macOS after adding the helper. The aggregate
  check now compiles/imports the baseline helper, exercises its `--help` path,
  verifies a synthetic release-evidence archive renders pull/export,
  extraction, APFS clone, perf marker, clean poweroff, and total timing fields,
  and verifies the missing-input error path.
- Scope note: this adds the repeatable reporting mechanism needed for the
  clean Apple Silicon product baseline. The actual clean-host baseline table is
  still pending until a durable external bundle image is available and the run
  is collected on a fresh host/cache.

### 2026-05-18: macOS Release Gate Orchestration

- Added `examples/os_mode_release_gate.py` as the canonical clean-host release
  gate command for digest-pinned OS bundle images. It runs the importer with
  explicit pull timing for a clean-shutdown smoke launch, then runs a separate
  fresh APFS clone through `examples/os_mode_perf.py`, archives release
  evidence, writes `baseline.md`, and records `release-gate-summary.json`.
- Validation:
  `make os-mode-checks` passed on macOS after adding the release-gate helper.
  The aggregate check now compiles/imports the helper, exercises its `--help`
  path, verifies digest-pinned image enforcement and product-cache naming,
  verifies the generated smoke importer command includes `--pull`, `--run`,
  `--strict-digest`, and `--reuse-extracted-output-dir`, and verifies the perf
  gate executes APFS clone before the perf command with expected PID 1/root
  guards.
- Scope note: this closes the local automation gap for the clean-host product
  baseline. It still does not publish the durable sample image or substitute
  for running that image on a clean Apple Silicon host.

### 2026-05-18: Portable Bundle Archive Publishing

- Added `examples/os_mode_publish_container_bundle.py --archive-output` to
  save a built OS-bundle image tag as a Docker-compatible archive, plus
  `--archive-sha256-output` to write a fresh SHA-256 sidecar.
- Added `--artifact-manifest-output`, which writes
  `libkrun.os-bundle.artifact.v1` JSON recording the bundle manifest digest,
  image tag, optional registry digest, optional archive path/checksum/size,
  load command, run command, and release-gate command.
- Validation:
  `make os-mode-checks` passed on macOS after adding archive publishing and the
  artifact manifest. The
  aggregate check now rejects `--archive-output` without `--image-tag`, rejects
  `--archive-sha256-output` without `--archive-output`, verifies
  `save_image_archive()` uses `docker save -o ... IMAGE`, verifies the archive
  SHA-256 sidecar writer, verifies existing archive destinations are not
  overwritten, verifies context-only artifact manifests, and verifies
  archive-backed artifact manifests prefer digest-pinned run/release-gate
  commands when a registry digest exists.
- Scope note: this provides a durable non-`/private/tmp` distribution fallback
  for sample bundles when registry credentials are unavailable. It is weaker
  than a registry-published digest-pinned image because a loaded local tag is
  mutable; clean-host release evidence should still prefer the registry digest
  path when available.

### 2026-05-18: Durable Local Sample Bundle Artifact

- Exported the existing local `linux/arm64` Debian systemd OS-bundle image to a
  durable archive outside `/private/tmp`:
  `os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.tar`.
- Source image metadata from Docker:
  - tag: `libkrun-osmode-debian-systemd-bundle:bookworm-arm64`
  - digest reference:
    `libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b`
  - platform: `linux/arm64`
- Artifact files:
  - archive size: `84050944` bytes
  - archive SHA-256:
    `744a93d6f3c26c14936b28eecd389260b0fea5b522c0d4829da9762589f06e9c`
  - sidecar:
    `os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.tar.sha256`
  - bundle manifest:
    `os_mode_artifacts/debian-systemd-bookworm-arm64/bundle-manifest.json`
  - source manifest:
    `os_mode_artifacts/debian-systemd-bookworm-arm64/source-manifest.json`
  - artifact manifest:
    `os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json`
- Validation:
  - `shasum -a 256 -c libkrun-osmode-debian-systemd-bundle-bookworm-arm64.tar.sha256`
    passed.
  - `python3 -m json.tool
    os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json`
    passed.
- Scope note: this satisfies the "otherwise provide a durable sample outside
  `/private/tmp`" local artifact gate. The clean-host baseline remains open
  until this archive or a registry-published equivalent is loaded on a clean
  Apple Silicon host and run through `examples/os_mode_release_gate.py`.

### 2026-05-18: Local Release-Gate Baseline From Durable Sample

- Fixed `examples/os_mode_collect_release_evidence.py` to copy perf timings
  from `os_mode_perf.py`'s real nested `timings` object into
  `release-evidence.json`. The host-independent fixture now uses the same
  nested perf schema, and `make os-mode-checks` passed after the fix.
- Ran `examples/os_mode_release_gate.py` against the durable local Debian
  systemd sample image using a repo-local cache and `--skip-pull`:
  `libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b`.
- Evidence directory:
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-local2/`.
- Result: passed.
  - smoke observed root `/dev/vda`
  - smoke observed PID 1 `systemd`
  - smoke observed console `ttyAMA0`
  - smoke observed network `skipped`
  - clean shutdown: yes
  - no stale `os_mode` or `gvproxy` processes remained after the run
- Baseline table from
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-local2/baseline.md`:

  | Label | Image pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | local durable Debian systemd sample | -/1684 | 0 | 115 | - | 841 | 843 | 845 | yes | 1707 |

- Scope note: this is a local Apple Silicon release-gate baseline from a
  repo-local cache, not a clean-host baseline. The clean-host Phase 23 item
  remains open until the archive or registry image is loaded on a fresh host
  and run with the same gate.

### 2026-05-18: Artifact-Manifest Release Gate

- Added `examples/os_mode_release_gate.py --artifact-manifest`, which loads a
  `libkrun.os-bundle.artifact.v1` JSON manifest, resolves a moved archive next
  to the manifest when needed, verifies the archive SHA-256, runs the recorded
  `docker load -i ...` or `podman load -i ...` command, and uses the manifest's
  digest-pinned image reference for smoke/perf validation.
- Validation:
  - `make os-mode-checks` passed after adding host-independent tests for
    artifact manifest parsing, moved-archive resolution, runtime override of
    the load command, load-command execution, and archive SHA-256 mismatch
    rejection.
  - Local end-to-end artifact-manifest gate passed with:
    `examples/os_mode_release_gate.py --artifact-manifest
    os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
    --cache-dir os_mode_artifacts/release-gate-cache-artifact
    --output-dir
    os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-local`.
  - `release-gate-summary.json` recorded the archive load command and artifact
    manifest path.
  - No stale `os_mode` or `gvproxy` processes remained after the run.
- Baseline table from
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-local/baseline.md`:

  | Label | Image pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | artifact-manifest local durable Debian systemd sample | -/1684 | 8020 | 110 | - | 824 | 826 | 830 | yes | 9785 |

- Scope note: this proves the archive-delivered sample can be loaded and run by
  the release gate on this Mac. It still is not a clean-host baseline because
  the host is the ongoing development machine.

### 2026-05-18: Fresh-Cache Artifact Release Gate

- Added and exercised `examples/os_mode_release_gate.py --require-clean-cache`
  for the artifact-manifest path. The gate now derives the expected bundle
  cache entry from the image reference and fails before loading/running the
  bundle when that entry already exists with files.
- Negative preflight behavior was observed first: the gate rejected
  `os_mode_artifacts/release-gate-cache-artifact-clean/...` because it already
  contained `.libkrun-os-bundle-import.json` and `libkrun-os-bundle`.
- Re-ran with a fresh cache directory:
  `examples/os_mode_release_gate.py --artifact-manifest
  os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
  --cache-dir os_mode_artifacts/release-gate-cache-artifact-clean-fresh
  --output-dir
  os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-fresh-local
  --require-clean-cache --build-command 'make BLK=1 NET=1
  CLANG=/opt/homebrew/opt/llvm/bin/clang'`.
- Result: passed.
  - archive load command: `docker load -i
    os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.tar`
  - cache preflight: `exists=false`, `entries=[]`, `clean=true`
  - smoke observed root `/dev/vda`
  - smoke observed PID 1 `systemd`
  - smoke observed console `ttyAMA0`
  - smoke observed network `skipped`
  - clean shutdown: yes
  - no stale `gvproxy` process remained after the run
- Baseline table from
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-fresh-local/baseline.md`:

  | Label | Image pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b | -/1684 | 7811 | 123 | - | 836 | 839 | 842 | yes | 9595 |

- Scope note: this is stronger than the previous artifact-manifest local run
  because it proves the release gate can enforce an initially empty derived
  bundle cache entry. It still is not a true clean-host baseline because the
  host remains the development machine.

### 2026-05-18: Clean-Cache Commands in Published Artifact Manifests

- Updated `examples/os_mode_publish_container_bundle.py` so generated
  `libkrun.os-bundle.artifact.v1` manifests record clean-cache release-gate
  commands. Registry digest commands now include `--require-clean-cache`, and
  archive-backed artifacts also record a `release_gate_from_artifact` command
  using `--artifact-manifest ARTIFACT_MANIFEST --require-clean-cache`.
- Updated the durable local Debian systemd artifact manifest under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/` to include those command
  fields, and revalidated it with `python3 -m json.tool`.
- Updated the README and `examples/os_mode.md` runbook snippets so release and
  clean-host baseline examples use `--require-clean-cache`.
- Validation:
  `make os-mode-checks` passed after updating the publisher self-test to verify
  both clean-cache command forms.

### 2026-05-18: Release Evidence Verifier

- Added `examples/os_mode_verify_release_evidence.py` to audit a release-gate
  evidence directory before its `baseline.md` is accepted as release or
  clean-host evidence.
- Added `make os-mode-verify-release-evidence EVIDENCE_DIR=...` as the normal
  verifier entrypoint. The target applies the clean-host acceptance flags by
  default and supports `ARTIFACT=1` and `PULL=1` for archive and registry
  evidence variants.
- The verifier checks `release-evidence.json`, `release-gate-summary.json`,
  `baseline.md`, copied artifact checksums and sizes, digest-pinned image
  identity, smoke root/PID 1/console/readiness markers, importer timing
  fields, optional perf timing fields, optional APFS metadata, optional
  macOS/arm64 host metadata, optional clean poweroff, optional artifact-manifest
  and archive-load evidence, and optional clean-cache preflight state.
- Host-independent validation:
  `make os-mode-checks` now compiles/imports the verifier and creates a
  synthetic release evidence archive. The positive case requires clean cache,
  absent cache entry, artifact manifest, artifact load, APFS, macOS/arm64,
  perf, clean poweroff, and pull evidence. The negative case proves the
  verifier rejects evidence whose clean-cache preflight reports that the cache
  entry already existed.
- Real evidence sanity check:
  `examples/os_mode_verify_release_evidence.py
  os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-fresh-local
  --require-clean-cache --require-cache-entry-absent
  --require-artifact-manifest --require-artifact-load --require-apfs
  --require-macos-arm64 --require-perf --require-clean-poweroff` passed against
  the fresh-cache artifact-manifest release evidence. It verified root
  `/dev/vda`, PID 1 `systemd`, console `ttyAMA0`, and readiness.
- Integrated the verifier into `examples/os_mode_release_gate.py` so a release
  gate run verifies its own generated archive after writing
  `release-gate-summary.json`. Host-independent checks exercise the integrated
  verifier path with clean-cache, artifact, APFS, macOS/arm64, perf, clean
  poweroff, and pull requirements.
- Split clean-cache and clean-host semantics in the release gate:
  `--require-clean-cache` now keeps its documented meaning of absent or empty,
  while `--require-cache-entry-absent` is the stricter clean-host baseline
  requirement. The stricter flag requires `--require-clean-cache`, is recorded
  in `release-gate-summary.json`, and is checked by the verifier when
  `--require-cache-entry-absent` is requested.
- Updated generated artifact-manifest release-gate commands, the durable local
  Debian systemd artifact manifest, the README, and `examples/os_mode.md` so
  clean-host baseline commands include both flags.
- Added `examples/os_mode_release_gate.py --clean-host-baseline` as the
  product-facing shortcut for those strict clean-host flags. It enables
  `--require-clean-cache` and `--require-cache-entry-absent`, records
  `clean_host_baseline=true` in `release-gate-summary.json`, and rejects
  registry-image runs that also use `--skip-pull`.
- Updated generated artifact-manifest command hints, the durable local Debian
  systemd artifact manifest, the README, and `examples/os_mode.md` to use the
  clean-host shortcut while the summary/verifier still records and checks the
  underlying explicit requirements.
- Real clean-host shortcut validation:
  `examples/os_mode_release_gate.py --artifact-manifest
  os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
  --cache-dir os_mode_artifacts/release-gate-cache-artifact-clean-host-shortcut
  --output-dir
  os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-host-shortcut-local
  --clean-host-baseline --build-command 'make BLK=1 NET=1
  CLANG=/opt/homebrew/opt/llvm/bin/clang'` passed. The summary recorded
  `clean_host_baseline=true`, `require_clean_cache=true`,
  `require_cache_entry_absent=true`, `cache_preflight.exists=false`,
  `cache_preflight.entries=[]`, and `cache_preflight.clean=true`.
  `make os-mode-verify-release-evidence
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-host-shortcut-local
  ARTIFACT=1` also passed. No stale `examples/os_mode` or `gvproxy` process
  remained after the run.
- Clean-host shortcut baseline from
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-host-shortcut-local/baseline.md`:

  | Label | Image pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b | -/1684 | 7646 | 114 | - | 842 | 845 | 848 | yes | 9778 |
- Real strict absent-cache validation:
  `examples/os_mode_release_gate.py --artifact-manifest
  os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
  --cache-dir os_mode_artifacts/release-gate-cache-artifact-absent
  --output-dir
  os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-absent-local
  --require-clean-cache --require-cache-entry-absent --build-command 'make
  BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang'` passed. The returned
  JSON included `verification.verified=true`, and the summary recorded
  `require_clean_cache=true`, `require_cache_entry_absent=true`,
  `cache_preflight.exists=false`, `cache_preflight.entries=[]`, and
  `cache_preflight.clean=true`. No stale `examples/os_mode` or `gvproxy`
  process remained after the run.
- Strict absent-cache baseline from
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-absent-local/baseline.md`:

  | Label | Image pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b | -/1684 | 6889 | 103 | - | 822 | 825 | 828 | yes | 8644 |
- Real integrated-gate validation:
  `examples/os_mode_release_gate.py --artifact-manifest
  os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
  --cache-dir os_mode_artifacts/release-gate-cache-artifact-verified
  --output-dir
  os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-verified-local
  --require-clean-cache --build-command 'make BLK=1 NET=1
  CLANG=/opt/homebrew/opt/llvm/bin/clang'` passed. The returned JSON included
  `verification.verified=true`, root `/dev/vda`, PID 1 `systemd`, console
  `ttyAMA0`, and readiness. `release-gate-summary.json` recorded
  `cache_preflight.exists=false`, `cache_preflight.entries=[]`,
  `cache_preflight.clean=true`, `require_clean_cache=true`, the artifact
  manifest path, and the archive load command. No stale `examples/os_mode` or
  `gvproxy` process remained after the run.
- Integrated-gate baseline from
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-verified-local/baseline.md`:

  | Label | Image pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b | -/1684 | 7083 | 107 | - | 837 | 840 | 844 | yes | 8788 |
- 2026-05-18 design-doc/product-contract update:
  `design_docs/full_linux_os_mode.md` now states that the macOS product launch
  unit is a prepared OCI image containing `/libkrun-os-bundle/`, that ordinary
  distro/application images are authoring inputs until converted, and that the
  normal startup path must avoid rebuilding `root.raw` by using cached bundle
  artifacts plus a fresh APFS clone. Added a host-independent importer test
  proving a generic image that lacks `/libkrun-os-bundle` is classified as an
  image-extraction failure and is rejected before APFS clone creation or HVF
  launch. `make os-mode-checks` passed after the change.
- 2026-05-18 clean-host acceptance helper update:
  added `examples/os_mode_clean_host_acceptance.py`, which wraps the strict
  clean-host verifier flags and prints the accepted baseline table for a
  completed release-evidence archive. Added
  `make os-mode-accept-clean-host EVIDENCE_DIR=...` as the corresponding
  release runbook target. The host-independent checks now py-compile the
  helper, check `--help`, import it, run the imported function against the
  synthetic strict clean-host evidence archive, and run the CLI with
  `--artifact --pull --json-output` to verify both printed baseline-table
  output and machine-readable `accepted=true` JSON. `make os-mode-checks`
  passed after the change.
- 2026-05-18 direct acceptance invocation hardening:
  set `examples/os_mode_clean_host_acceptance.py` executable because
  `make os-mode-accept-clean-host` invokes it directly, and added a direct
  `examples/os_mode_clean_host_acceptance.py --help` host-independent check so
  executable-bit regressions are caught.
- 2026-05-18 acceptance make-target coverage:
  added a host-independent `make -n os-mode-accept-clean-host
  EVIDENCE_DIR=... ARTIFACT=1 PULL=1` check so the release runbook target is
  covered by `make os-mode-checks` and must keep forwarding the archive and
  pull proof requirements to `examples/os_mode_clean_host_acceptance.py`.
- 2026-05-18 stale-baseline acceptance rejection:
  extended the clean-host acceptance CLI test to corrupt `baseline.md`, require
  the helper to exit nonzero, and verify `--json-output` records
  `accepted=false` with the stale-baseline error before restoring the archive.
  This keeps the final clean-host table workflow tied to regenerated release
  evidence rather than hand-edited Markdown.
- 2026-05-18 acceptance strict-flag guard:
  hardened `examples/os_mode_clean_host_acceptance.py` so evidence archives
  that contain copied artifact-manifest proof require `--artifact`/`ARTIFACT=1`,
  and archives whose smoke importer command records `--pull` require
  `--pull`/`PULL=1`. Host-independent checks now verify both missing-flag
  rejections before accepting the synthetic strict clean-host archive.
- 2026-05-18 acceptance table-output support:
  added `examples/os_mode_clean_host_acceptance.py --table-output` so the final
  clean-host baseline table can be written as standalone Markdown only after
  strict archive acceptance passes. Host-independent checks verify the table
  file is written for accepted evidence and is not written for rejected stale
  baseline evidence.
- 2026-05-18 acceptance make-output forwarding:
  extended `make os-mode-accept-clean-host` with optional `JSON_OUTPUT=...`
  and `TABLE_OUTPUT=...` variables, forwarding them to the acceptance helper.
  The host-independent dry-run check now verifies the make target forwards
  archive/pull requirements and output paths together.
- 2026-05-18 acceptance output atomicity hardening:
  made `examples/os_mode_clean_host_acceptance.py` validate all requested
  success output paths before writing any accepted artifacts. Host-independent
  checks now verify an existing `--table-output` path causes a nonzero exit,
  writes `accepted=false` JSON when requested, and does not overwrite the
  existing table file.
- 2026-05-18 acceptance output path collision guard:
  made the acceptance helper reject identical `--json-output` and
  `--table-output` paths before writing anything. Host-independent checks now
  verify the same-path rejection exits nonzero, explains the error, and leaves
  no output artifact behind.
- 2026-05-18 runbook make-directory correction:
  updated README and `examples/os_mode.md` release-evidence verification and
  clean-host acceptance examples to use `make -C ..` from the documented
  `examples` working directory, avoiding accidental invocation outside the repo
  root Makefile.
- 2026-05-18 baseline-wrapper acceptance integration:
  extended `examples/os_mode_clean_host_baseline.py` with optional
  `--accept-json-output` and `--accept-table-output`. When supplied, the
  wrapper runs `os_mode_clean_host_acceptance.py` after preflight and release
  gate completion, passing `--artifact` for archive manifests and `--pull` for
  registry-image runs. Host-independent checks verify command construction and
  execution order for the archive path and `--pull` selection for the registry
  path.
- 2026-05-18 baseline-wrapper acceptance-output preflight:
  made `examples/os_mode_clean_host_baseline.py` validate acceptance output
  destinations before running preflight or release-gate commands. It now
  rejects identical acceptance output paths, acceptance outputs that collide
  with the preflight JSON or release-evidence output directory, and already
  existing acceptance output files. Host-independent checks cover those early
  rejections.
- 2026-05-18 baseline-wrapper acceptance-output parent check:
  extended the baseline wrapper's early acceptance-output validation to reject
  output paths whose parent directories do not exist before running preflight
  or release-gate commands. Host-independent checks cover the missing-parent
  rejection.
- 2026-05-18 artifact-manifest clean-host baseline command update:
  updated `examples/os_mode_publish_container_bundle.py` so generated
  `libkrun.os-bundle.artifact.v1` manifests include
  `--accept-json-output ACCEPTANCE_JSON` and
  `--accept-table-output ACCEPTED_BASELINE_MD` in clean-host baseline command
  templates. Host-independent publisher checks now require those placeholders.
- 2026-05-18 release-evidence artifact-manifest command verification:
  extended `examples/os_mode_verify_release_evidence.py` so archived artifact
  manifests must carry clean-host baseline command templates with accepted
  JSON/table output placeholders. Host-independent checks now corrupt the
  template and require the release-evidence verifier to reject it.
- 2026-05-18 durable artifact-manifest drift check:
  added an optional host-independent check for the local durable Debian systemd
  artifact manifest under `os_mode_artifacts/` when that ignored artifact is
  present. The check verifies its clean-host baseline command templates include
  accepted JSON/table output placeholders, so local sample metadata does not
  silently lag the publisher.
- 2026-05-18 direct acceptance early-output validation:
  moved `examples/os_mode_clean_host_acceptance.py` output-argument validation
  ahead of release-evidence verification, so bad `--json-output` or
  `--table-output` arguments fail before the helper reads or verifies an
  archive. Host-independent checks now invoke the CLI with a missing evidence
  directory and identical JSON/table output paths, requiring the output-path
  error to win and no output artifact to be created.
- 2026-05-18 clean-host baseline Makefile entrypoint:
  added `make os-mode-clean-host-baseline` as a root-level wrapper for
  `examples/os_mode_clean_host_baseline.py`. It requires `OUTPUT_DIR` plus
  either `IMAGE` or `ARTIFACT_MANIFEST`, and forwards cache, runtime,
  build-command provenance, preflight, accepted JSON/table output, and
  print-only options. The
  host-independent check now dry-runs the target and verifies those flags reach
  the baseline helper.
- 2026-05-18 clean-host baseline Makefile artifact strictness:
  updated `make os-mode-clean-host-baseline` so `IMAGE` is still forwarded when
  `ARTIFACT_MANIFEST` is set, and fixed
  `examples/os_mode_clean_host_baseline.py` to forward that explicit image to
  both the preflight and release-gate commands. This preserves the downstream
  mismatch guards, which reject an explicit image that differs from the
  artifact manifest's `digest_ref`. Host-independent checks now dry-run the
  artifact-manifest Make path and directly exercise the helper command builder,
  requiring both the manifest flag and image argument to reach the child
  commands.
- 2026-05-18 clean-host preflight explicit-image recording:
  updated `examples/os_mode_clean_host_preflight.py` so the recorded
  `release_gate_command` includes the explicit `IMAGE` when both `IMAGE` and
  `--artifact-manifest` are supplied. Host-independent checks now verify a
  matching explicit image is preserved in the report and that a mismatched
  image/artifact digest is rejected during preflight.
- 2026-05-18 clean-host preflight artifact-manifest binding:
  tightened `examples/os_mode_release_gate.py` so `--clean-host-baseline`
  validation rejects a preflight report produced for a different artifact
  manifest, and rejects artifact-manifest preflight reports on registry-only
  release gates. Host-independent checks now call the release-gate preflight
  validator directly for matching, mismatched, and registry/artifact-mixed
  cases.
- 2026-05-18 archived preflight artifact-manifest verification:
  extended `examples/os_mode_verify_release_evidence.py` so offline
  clean-host verification also binds archived `clean-host-preflight.json` to
  the same artifact manifest recorded by `release-gate-summary.json`. The
  verifier now rejects preflight reports whose artifact manifest path or
  digest does not match the release evidence. Host-independent checks corrupt
  the archived preflight artifact path and require verification to fail.
- 2026-05-18 archived preflight command value verification:
  tightened the offline release-evidence verifier so the archived preflight's
  recorded `release_gate_command` must use the expected `--output-dir`,
  `--preflight-json`, and, for artifact-delivered evidence,
  `--artifact-manifest` paths. Host-independent checks now corrupt the
  command's artifact-manifest value and require verification to reject the
  archive.
- 2026-05-18 archived preflight command image-reference verification:
  extended the offline release-evidence verifier to scan digest-pinned image
  references in the archived preflight's `release_gate_command`. Registry
  evidence must include the release `image_ref`, and any digest-pinned image
  reference present in the command must match the archived release evidence.
  Host-independent checks now inject a different digest-pinned image into the
  recorded command and require verification to reject the archive.
- 2026-05-18 registry preflight image-reference verifier coverage:
  added a synthetic registry-delivered clean-host release-evidence case to
  `ci/os_mode_host_checks.sh`. It verifies that offline clean-host acceptance
  succeeds when the archived preflight command includes the release
  digest-pinned image, and rejects the same evidence when that image argument
  is removed from the recorded command.
- 2026-05-18 smoke importer image-reference verifier binding:
  tightened `examples/os_mode_verify_release_evidence.py` so the archived
  `smoke_importer_command` must contain `--image` with the release
  digest-pinned `image_ref`, and any digest-pinned image reference in that
  command must match the evidence image. Host-independent checks now corrupt
  the smoke importer command's image value and require verification to reject
  the archive.
- 2026-05-18 artifact-load archive verifier binding:
  tightened `examples/os_mode_verify_release_evidence.py` so artifact-delivered
  evidence verifies the artifact archive path, SHA-256, and size from the
  archived `artifact-manifest.json`, then requires
  `release-gate-summary.json`'s `artifact_load_command -i` path to match that
  archive. Host-independent checks now corrupt the load command archive path
  and require verification to reject the archive.
- 2026-05-18 smoke importer cache-entry verifier binding:
  tightened `examples/os_mode_verify_release_evidence.py` so the archived
  `smoke_importer_command --output-dir` must match the release-gate summary's
  derived bundle cache entry. Host-independent checks now corrupt that
  output-dir value and require verification to reject the archive, preventing
  evidence from mixing a clean-cache preflight for one cache entry with an
  importer run from another.
- 2026-05-18 smoke importer output verifier binding:
  tightened the offline verifier so the archived `smoke_importer_command`
  must include a `--smoke-output` value whose basename matches the source
  smoke JSON recorded in release-evidence artifact metadata. Host-independent
  checks now corrupt the command's smoke-output value and require verification
  to reject the archive.
- 2026-05-18 perf output verifier binding:
  tightened the offline verifier so release evidence that requires perf must
  include a `perf_command` with `--require-pid1-marker` and an `--output`
  basename matching the source perf JSON recorded in artifact metadata.
  Host-independent checks now corrupt the perf command output value and require
  verification to reject the archive.
- 2026-05-18 perf clone/root verifier binding:
  tightened the offline verifier so release evidence that requires perf must
  include a `perf_clone_command` using `os_mode_apfs_clone.sh`, sourcing the
  bundle root disk and producing the same root disk path passed to
  `perf_command --root-disk`. Host-independent checks now corrupt the perf
  clone destination and require verification to reject the archive.
- 2026-05-18 archived perf timing verifier binding:
  tightened the offline verifier so `release-evidence.json` perf timings must
  match the archived `perf.json` timings used to produce them. Host-independent
  checks now corrupt the archived `ready_ms` timing, refresh the artifact
  checksum metadata, and require verification to reject the archive.
- 2026-05-18 archived smoke marker verifier binding:
  tightened the offline verifier so archived `smoke.json` must independently
  record `ready=true`, no failure, the expected root, PID 1, console list, and
  the same network marker summarized in `release-evidence.json`. Host-independent
  checks now corrupt the archived smoke console list, refresh the artifact
  checksum metadata, and require verification to reject the archive.
- 2026-05-18 archived perf marker verifier binding:
  tightened the offline verifier so `--require-perf` evidence must prove the
  perf run observed the same expected root, PID 1, and console recorded in the
  bundle manifest, must not observe `init.krun`, and must keep archived
  `perf.json` marker fields in sync with `release-evidence.json`. If perf
  records a network marker, the archived perf JSON must also match the release
  summary. Host-independent checks now corrupt the archived perf PID 1 marker,
  refresh artifact checksum metadata and baseline output, and require
  verification to reject the archive.
- 2026-05-18 first-boot-log baseline timing fix:
  added structured timing fields to `examples/os_mode_smoke.py`, copied those
  timings into release evidence, and made the baseline table use smoke's
  `first_kernel_log_ms` for the `First log ms` column. The perf helper now
  records `first_kernel_log_ms` only for actual early boot lines such as
  `Booting Linux`, `Linux version`, or `Kernel command line`; a host warning
  such as `[2026-...]` and timestamped `KRUN_OSMODE` readiness lines are not
  counted as first kernel output. The offline verifier now requires archived
  smoke timing fields to match `release-evidence.json`, while perf first-log
  timing is optional and verified if present. Host-independent checks cover
  smoke timing capture, collector fields, table value, verifier checks, and
  the host-warning negative case.
- 2026-05-18 strict local clean-host-baseline rehearsal:
  ran `make os-mode-clean-host-baseline` with the durable artifact manifest,
  a fresh `/private/tmp/libkrun-osmode-clean-host-rehearsal-cache-current4`
  cache root, acceptance JSON, and accepted baseline table output. The archive
  under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local4/`
  passed strict acceptance with `artifact_manifest=true`, `artifact_load=true`,
  `clean_cache=true`, `cache_entry_absent=true`, `apfs=true`,
  `macos_arm64=true`, `perf=true`, `clean_poweroff=true`, and
  `clean_host_preflight=true`. Accepted local rehearsal timings:
  export `1684 ms`, bundle extraction `8634 ms`, APFS clone `115 ms`, first
  boot log `125 ms`, root marker `965 ms`, PID 1 marker `969 ms`, ready
  marker `973 ms`, clean poweroff `yes`, total `10475 ms`. This is still local
  rehearsal evidence, not the final clean Apple Silicon host baseline. This
  run predates explicit archive-load elapsed timing in `release-evidence.json`,
  so it is now historical timing evidence rather than current strict artifact
  acceptance evidence.
- 2026-05-18 archived smoke boot-log verifier binding:
  tightened `examples/os_mode_collect_release_evidence.py` and
  `examples/os_mode_verify_release_evidence.py` so the smoke timing field
  `first_kernel_log_ms` must be backed by an archived `output_lines` entry
  that looks like an early kernel boot line. The collector now rejects smoke
  JSON without timing markers or without a line such as `Booting Linux`,
  `Linux version`, or `Kernel command line`; the offline verifier repeats that
  check against archived release evidence even when artifact checksums are
  refreshed. Host-independent checks now cover both the collector rejection and
  verifier rejection paths.
- 2026-05-18 artifact load timing evidence:
  extended artifact-delivered release gates to record elapsed Docker/Podman
  archive load time as `artifact.load_ms`, made the release-evidence verifier
  require a non-negative load timing when `--require-artifact-load` is set, and
  changed the baseline table's first timing column to
  `Image load/pull/export ms`. Host-independent checks now reject artifact
  evidence with missing or invalid load timing and expect registry-style rows
  to render `-/pull/export`.
- 2026-05-18 strict local artifact-load rehearsal:
  reran `make os-mode-clean-host-baseline` with the durable artifact manifest,
  a fresh `/private/tmp/libkrun-osmode-clean-host-rehearsal-cache-current5`
  cache root, acceptance JSON, and accepted baseline table output so the local
  rehearsal exercises the current artifact-load timing contract. The archive
  under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local5/`
  passed strict acceptance with `artifact_manifest=true`, `artifact_load=true`,
  `clean_cache=true`, `cache_entry_absent=true`, `apfs=true`,
  `macos_arm64=true`, `perf=true`, `clean_poweroff=true`, and
  `clean_host_preflight=true`. Accepted local rehearsal timings:
  artifact load `895 ms`, export `1684 ms`, bundle extraction `11483 ms`,
  APFS clone `129 ms`, first boot log `114 ms`, root marker `916 ms`, PID 1
  marker `920 ms`, ready marker `926 ms`, clean poweroff `yes`, total
  `13626 ms`. The accepted table renders load/pull/export as `895/-/1684`.
  Follow-up explicit checks also passed:
  `make os-mode-verify-release-evidence
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local5
  ARTIFACT=1`, `make os-mode-accept-clean-host
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local5
  ARTIFACT=1`, `make os-mode-checks`, `git diff --check`, and the
  `examples`/`ci`/`design_docs` pycache scan. This is still local rehearsal
  evidence, not the final clean Apple Silicon host baseline.
- 2026-05-18 clean-host acceptance evidence checklist:
  extended `examples/os_mode_clean_host_acceptance.py` so accepted JSON
  includes an `evidence_checklist` mapping the accepted baseline row back to
  concrete archived facts: `clean cache`, `absent cache entry`, `APFS output`,
  `macOS arm64 host`, clean-host preflight, guest OS markers, first boot log
  timing, perf marker timings, clean poweroff, baseline timing fields, and
  artifact-load or registry-pull timing as applicable. Host-independent checks
  now require the Python API and CLI acceptance JSON to include passed
  checklist entries for clean-cache, absent-cache, guest OS markers, first boot
  log timing, baseline marker timing, baseline row timing,
  load/pull/export timing, and artifact delivery, and also monkeypatch a
  failed checklist item to prove acceptance rejects it.
- 2026-05-18 host-side launch process evidence:
  fixed `examples/os_mode_collect_release_evidence.py` to preserve the real
  process metadata emitted by `examples/os_mode_smoke.py`: `launcher_pid`,
  `process_parent_pid`, `process_pid`, and compatibility `child_pid`. The
  offline release-evidence verifier now rejects archives whose smoke JSON
  lacks valid process metadata or whose release-evidence summary does not
  match the archived smoke JSON. The clean-host acceptance checklist also
  exposes this as a named `host-side launcher process` item, and
  host-independent checks cover the missing-`process_pid` rejection path.
- 2026-05-18 archived smoke command binding:
  tightened `examples/os_mode_verify_release_evidence.py` so archived smoke
  evidence must bind together the smoke helper command, executed
  `examples/os_mode` command, release-evidence command summary, APFS clone
  command, and bundle `root.raw`. The verifier now requires the smoke command
  to execute host-side `examples/os_mode`, permits only the validation
  `--poweroff-after-ready` suffix beyond the recorded production launch
  command, and verifies that the launch root disk is the APFS clone
  destination. Host-independent checks now corrupt the archived smoke
  `os_mode_command`, refresh the artifact checksum metadata, and require the
  verifier to reject the archive.
- 2026-05-18 archived smoke bundle path binding:
  tightened the command-binding verifier further so the archived smoke bundle
  metadata must match the extracted bundle directory, digest-pinned image
  reference, bundle kind, schema version, platform, `root.raw` digest, APFS
  clone source, and APFS clone destination. The verifier now rejects an archive
  that points at a same-basename `root.raw` outside the extracted bundle
  directory even if the release-evidence command summary is edited to match
  that bad path. Host-independent checks cover this by corrupting the archived
  smoke root disk path, refreshing the smoke artifact checksum metadata, and
  requiring verification to fail before acceptance.
- 2026-05-18 bundle provenance verifier binding:
  tightened `examples/os_mode_verify_release_evidence.py` so the
  release-evidence bundle summary must match the archived bundle manifest for
  bundle kind, schema version, platform, source image, source digest, root disk
  digest, kernel digest, initramfs digest, expected root, expected console, and
  expected PID 1. Archived smoke bundle metadata must also match the manifest's
  source image and source digest. Host-independent checks now corrupt archived
  smoke `source_digest` and release-evidence `kernel_sha256`, refresh artifact
  checksum and baseline metadata as needed, and require the verifier to reject
  both archives.
- 2026-05-18 bundle provenance acceptance checklist:
  extended `examples/os_mode_clean_host_acceptance.py` so accepted JSON names
  bundle provenance as an explicit checklist item. The checklist ties the
  accepted row to the archived bundle manifest's source image, source digest,
  root disk digest, kernel digest, initramfs digest, expected root, expected
  console, expected PID 1, and the digest-pinned imported bundle image recorded
  by smoke evidence. Host-independent checks require this item to pass for
  strict synthetic evidence.
- 2026-05-18 command-binding acceptance checklist:
  extended `examples/os_mode_clean_host_acceptance.py` so accepted JSON also
  names the host-side launch command binding as a checklist item. The
  checklist now confirms that the release-evidence command summary matches the
  archived smoke command metadata, that the smoke helper executed host-side
  `examples/os_mode`, and that the launch root disk is the APFS clone
  destination. Host-independent checks require this checklist item to pass for
  strict synthetic evidence.
- 2026-05-18 strict local process-evidence checklist rehearsal:
  reran `make os-mode-clean-host-baseline` with the durable artifact manifest,
  a fresh `/private/tmp/libkrun-osmode-clean-host-rehearsal-cache-current8`
  cache root, acceptance JSON, and accepted baseline table output so the
  standard acceptance artifact itself includes the enforced
  `evidence_checklist` and host-side process metadata. The archive under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8/`
  passed strict acceptance with `artifact_manifest=true`, `artifact_load=true`,
  `clean_cache=true`, `cache_entry_absent=true`, `apfs=true`,
  `macos_arm64=true`, `perf=true`, `clean_poweroff=true`, and
  `clean_host_preflight=true`. Accepted local rehearsal timings:
  artifact load `933 ms`, export `1684 ms`, bundle extraction `17812 ms`,
  APFS clone `401 ms`, first boot log `208 ms`, root marker `2093 ms`, PID 1
  marker `2103 ms`, ready marker `2115 ms`, clean poweroff `yes`, total
  `22310 ms`. The accepted table renders load/pull/export as `933/-/1684`.
  The accepted checklist includes `host-side launcher process` with
  `launcher_pid=74750`, `process_parent_pid=74750`, and `process_pid=74751`.
  After adding the command-binding checklist item, strict acceptance was rerun
  without overwriting the original acceptance artifact and wrote
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.command-binding.acceptance.json`
  plus
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.command-binding.baseline.md`.
  That refreshed acceptance checklist includes `host-side launch command
  binding`, proving the smoke helper executed host-side `examples/os_mode`
  with the APFS clone destination as the root disk.
  After adding the bundle-provenance checklist item, strict acceptance was
  rerun again and wrote
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.provenance.acceptance.json`
  plus
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.provenance.baseline.md`.
  That refreshed checklist includes `bundle provenance`, tying the accepted
  row to source image
  `libkrun-osmode-debian-systemd:bookworm-arm64`, source digest
  `libkrun-osmode-debian-systemd@sha256:de7f098a60e5de093cc9ffa3e8a9159100bd5e56809f1926a66686901bca40f2`,
  root disk digest
  `cf07d9a0cdb84f505b529ea72494c760fabb5c1fd8a400c569eef314a5590971`,
  and imported bundle image
  `libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b`.
  This is still local rehearsal evidence, not the final clean Apple Silicon
  host baseline.
- 2026-05-18 bundle provenance acceptance evidence expansion:
  `examples/os_mode_clean_host_acceptance.py` now prints platform, kernel
  digest, initramfs digest, expected root, expected console, and expected PID
  1 in the `bundle provenance` checklist evidence string, in addition to the
  source image, source digest, root disk digest, and imported bundle image it
  already verified. Strict acceptance was rerun without overwriting the earlier
  evidence and wrote
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.audit.acceptance.json`
  plus
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.audit.baseline.md`.
  This local8 archive and its accepted tables are now historical under the
  current verifier because they predate the required `image_was_explicit`
  field in `release-gate-summary.json`.
- 2026-05-18 macOS product completion audit:
  `design_docs/full_linux_os_mode.md` now includes a compact requirement to
  validation matrix for the container-image-to-host-libkrun/HVF product path.
  The matrix keeps the clean Apple Silicon baseline as the only open row and
  explicitly treats Linux/KVM parity as deferred portability work rather than
  a blocker for the current macOS product path.
- 2026-05-18 registry-pull acceptance checklist coverage:
  `ci/os_mode_host_checks.sh` now asserts that strict synthetic acceptance
  with `pull=True` includes a passed `registry pull` checklist item, both
  through the Python API result and through the CLI JSON output. This closes
  the coverage gap where artifact-delivery evidence was checked explicitly but
  registry-delivery evidence could have disappeared from the checklist without
  failing host-independent checks.
- 2026-05-18 guest-marker checklist tightening:
  `examples/os_mode_clean_host_acceptance.py` now makes the `guest OS markers`
  checklist item require the verifier's observed root, PID 1, and console to
  match the release-evidence bundle expectations, and also requires the smoke
  summary to report the same expected root, PID 1, and console. The
  host-independent checks now call `acceptance_checklist()` with a deliberately
  mismatched verified root and require the `guest OS markers` item to fail.
- 2026-05-18 perf-marker checklist tightening:
  `examples/os_mode_clean_host_acceptance.py` now makes the `perf markers`
  checklist item require the perf summary's observed root, PID 1, and console
  to match the release-evidence bundle expectations in addition to requiring
  the timing markers. The host-independent checks temporarily write a
  mismatched perf root into synthetic release evidence and require the `perf
  markers` checklist item to fail before restoring the good evidence.
- 2026-05-18 first-kernel-log checklist tightening:
  `examples/os_mode_clean_host_acceptance.py` now makes the `first boot log
  timing` checklist item require both a non-negative `first_kernel_log_ms`
  timing and an archived smoke output line that matches the release verifier's
  early-kernel-line detector. The host-independent checks temporarily replace
  synthetic smoke output with only `KRUN_OSMODE: ready` and require the `first
  boot log timing` checklist item to fail before restoring the good smoke
  artifact.
- 2026-05-18 clean-poweroff checklist tightening:
  `examples/os_mode_clean_host_acceptance.py` now makes the `clean poweroff`
  checklist item require archived smoke `exit_code=0`, no failure, no timeout,
  and an executed command that is the archived host-side `examples/os_mode`
  command plus `--poweroff-after-ready`. The host-independent checks
  temporarily remove the poweroff flag from synthetic smoke evidence and
  require the `clean poweroff` checklist item to fail before restoring the good
  smoke artifact.
- 2026-05-18 required acceptance-checklist contract:
  `examples/os_mode_clean_host_acceptance.py` now has an explicit required
  checklist-name contract for final acceptance. `accept_evidence()` still
  rejects any failed checklist item, and now also rejects invalid, duplicate,
  or missing checklist items, including conditional `artifact delivery` and
  `registry pull` items when those modes are required. Host-independent checks
  monkey-patch the checklist down to a single passed item and require
  acceptance to fail with a missing-required-items error.
- 2026-05-18 acceptance-checklist shape coverage:
  `ci/os_mode_host_checks.sh` now also monkey-patches otherwise valid
  acceptance checklists with a duplicate `clean cache` item and with an
  unnamed passed item, requiring `accept_evidence()` to reject both shapes.
  This gives direct coverage for all three checklist contract failures:
  missing required item, duplicate item, and invalid item.
- 2026-05-18 acceptance-checklist invalid-item ordering:
  `examples/os_mode_clean_host_acceptance.py` now validates checklist shape
  before collecting failed checklist names, so non-dict checklist entries are
  reported as `acceptance checklist has invalid items` instead of crashing
  while formatting a failure. Host-independent checks now monkey-patch a
  non-dict checklist entry and require the invalid-item error path.
- 2026-05-18 acceptance-checklist evidence shape:
  `examples/os_mode_clean_host_acceptance.py` now requires every checklist item
  to have a boolean `passed` field and non-empty string `evidence`, in addition
  to a non-empty string `name`. Host-independent checks monkey-patch one item
  with a non-boolean `passed` value and another with empty evidence, requiring
  both to fail through the invalid-item path.
- 2026-05-18 required checklist in acceptance JSON:
  `examples/os_mode_clean_host_acceptance.py` now writes `required_checklist`
  into accepted JSON results, so the artifact itself records which checklist
  item names were mandatory for that run. Host-independent checks require the
  Python API result and CLI JSON output to include the same required checklist,
  including conditional `artifact delivery` and `registry pull` entries.
- 2026-05-18 unexpected acceptance-checklist item rejection:
  `examples/os_mode_clean_host_acceptance.py` now rejects checklist rows whose
  names are not in the required checklist for the selected acceptance mode.
  The failed-checklist host test now mutates an existing required item instead
  of appending an extra failed row, and a new host-independent check appends an
  `unexpected item` row and requires acceptance to reject it.
- 2026-05-18 required/evidence checklist parity:
  `ci/os_mode_host_checks.sh` now requires the accepted Python API result and
  CLI JSON output to have `required_checklist` exactly match the ordered names
  in `evidence_checklist`. This makes the acceptance artifact self-auditing:
  each required checklist name must have exactly one corresponding evidence row.
- 2026-05-18 required/evidence checklist order enforcement:
  `examples/os_mode_clean_host_acceptance.py` now enforces the same ordered
  checklist-name parity inside `accept_evidence()`, rejecting checklists whose
  names are all present but out of order. Host-independent checks swap the
  first two evidence checklist rows and require the acceptance helper to reject
  the reordered checklist.
- 2026-05-18 acceptance JSON schema version:
  `examples/os_mode_clean_host_acceptance.py` now writes `schema_version=1` in
  both accepted and rejected JSON payloads. Host-independent checks require the
  Python API result, CLI accepted JSON, CLI output-collision rejection JSON,
  and CLI stale-baseline rejection JSON to record that schema version.
- 2026-05-18 acceptance JSON schema documentation:
  README.md, `examples/os_mode.md`, and `design_docs/full_linux_os_mode.md`
  now describe `schema_version=1` alongside `required_checklist` and
  `evidence_checklist`, so the documented acceptance JSON contract matches the
  helper output.
- 2026-05-18 exact checklist-order documentation:
  `design_docs/full_linux_os_mode.md` now spells out the exact ordered
  `required_checklist`/`evidence_checklist` names for archive-delivered
  evidence and the registry-delivered substitution. This matches
  `examples/os_mode_clean_host_acceptance.py::required_check_names()` rather
  than a shortened prose checklist.
- 2026-05-18 conditional checklist-mode coverage:
  `ci/os_mode_host_checks.sh` now directly checks
  `required_check_names()` and `validate_required_checklist()` for all
  combinations of artifact delivery and registry pull requirements. The
  host-independent checks require archive-only acceptance to exclude
  `registry pull`, registry-only acceptance to exclude `artifact delivery`,
  and both single-mode validators to reject a checklist contaminated with the
  other delivery mode's conditional item.
- 2026-05-18 clean-host preflight JSON requirement:
  `examples/os_mode_clean_host_preflight.py` now requires `--json-output` for
  CLI use and treats programmatic preflight runs without a JSON output path as
  failed. This keeps an `ok=true` preflight from producing a release-gate
  command that cannot satisfy `os_mode_release_gate.py --clean-host-baseline
  --preflight-json ...`. Host-independent checks now require the generated
  release-gate command to include `--preflight-json` and the exact preflight
  JSON path, and require a missing JSON output path to fail preflight.
- 2026-05-18 release-gate preflight command binding:
  `examples/os_mode_release_gate.py` now validates the preflight report's
  recorded `release_gate_command` before running a clean-host baseline. It
  requires `schema_version=1`, `ok=true`, and an empty `errors` array before
  trusting the preflight report.
  requires the command executable to be `os_mode_release_gate.py`,
  `--preflight-json` to point at the JSON file being consumed, `--output-dir`
  to match the release evidence output directory, an explicit `--cache-dir` to
  identify the cache root, `--runtime` to match the gate's selected
  Docker/Podman mode, cache options to resolve to the same absent cache entry,
  positional image arguments to match the selected digest-pinned image, and
  the artifact-manifest or registry-image mode to match the release gate
  request. The offline release-evidence verifier now checks the helper name,
  runtime option, cache options, omitted `--name` for custom cache entries,
  and repeated command options too.
  The live release gate also rejects preflight JSON whose runtime metadata is
  missing, whose requested runtime does not match the gate request, or whose
  selected runtime is empty, invalid, or inconsistent with an explicit
  requested runtime. The offline verifier applies the same runtime value
  checks to archived preflight evidence.
  The live release gate now also rejects edited preflight JSON whose host is
  not macOS/arm64 or whose bundle-cache/output APFS checks are missing or
  failed, or whose `created_at_utc` is not a valid UTC timestamp, before any
  image load, clone, or guest launch.
  Host-independent checks mutate each command binding and require the release
  gate or verifier to reject the mismatched preflight before any guest launch.
- 2026-05-18 clean-host output freshness hardening:
  `examples/os_mode_release_gate.py --clean-host-baseline` now rejects
  `--allow-existing-output-dir` directly, and
  `examples/os_mode_clean_host_preflight.py` now rejects both
  `--allow-existing-output-dir` and `--allow-existing-empty-cache-entry` so a
  passing preflight cannot describe a reusable output directory or preexisting
  cache entry. Both the live preflight binding check and offline
  release-evidence verifier reject archived preflight commands that include
  `--allow-existing-output-dir` or `--skip-pull`, and both validators now
  reject repeated options, unknown options, and trailing positional arguments
  in those recorded commands. They also require the preflight-generated option
  order and require `--clean-host-baseline` to be the final argument, matching
  the command emitted by the preflight helper.
  Host-independent checks cover the CLI guard, preflight flag rejection, the
  live preflight-command validator, and the offline archive verifier.
- 2026-05-18 explicit artifact image invocation tracking:
  `examples/os_mode_release_gate.py` now preserves whether `IMAGE` was
  explicitly supplied before resolving `--artifact-manifest`, records that as
  `image_was_explicit` in `release-gate-summary.json`, and requires the
  clean-host preflight command to include or omit the positional image to match
  that invocation mode. `examples/os_mode_verify_release_evidence.py` enforces
  the same archived summary/preflight relationship, and host-independent checks
  cover artifact-only and explicit-image artifact gates.
- 2026-05-18 clean-host summary flag enforcement:
  `examples/os_mode_verify_release_evidence.py --require-clean-host-preflight`
  now also requires `release-gate-summary.json` to record
  `clean_host_baseline=true`, so an archive with copied preflight JSON cannot
  pass as a clean-host baseline unless the gate summary records the strict
  baseline mode. Host-independent checks mutate the summary flag and require
  rejection.
- 2026-05-18 release-gate summary acceptance item:
  `examples/os_mode_clean_host_acceptance.py` now includes a required
  `release-gate summary` checklist item. It exposes the strict summary
  contract already enforced by the verifier: `schema_version=1`,
  `clean_host_baseline=true`, clean-cache requirements,
  boolean `image_was_explicit`, and matching archived release-evidence,
  baseline-table, and preflight-JSON paths. Host-independent checks require
  the item in accepted evidence and prove it fails if the summary no longer
  records clean-host baseline mode.
- 2026-05-18 release-gate image-mode acceptance binding:
  The `release-gate summary` checklist item now ties `image_was_explicit` to
  the archived clean-host preflight `release_gate_command` positional
  arguments. Registry evidence must show an explicit positional image, while
  artifact-manifest evidence must show either no positional image when the
  artifact supplied the digest reference or exactly the release image when an
  explicit image was supplied. Host-independent checks mutate artifact
  evidence to make `image_was_explicit` disagree with the preflight command and
  require the acceptance checklist item to fail.
- 2026-05-18 stale local8 acceptance check:
  Attempting to re-accept
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8/`
  with the current acceptance helper failed with
  `summary image_was_explicit must be a boolean`, as expected for a historical
  archive collected before that summary field existed. The failure JSON was
  recorded at
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.image-mode.acceptance.json`.
  `design_docs/full_linux_os_mode.md` now uses placeholder paths in the final
  acceptance command so the documented command cannot be mistaken for a
  currently valid release gate against stale local rehearsal evidence.
- 2026-05-18 final clean-host command dry run:
  `make os-mode-clean-host-baseline ... PRINT_ONLY=1` passed against the
  durable Debian systemd artifact manifest with fresh intended output,
  cache, preflight, acceptance JSON, and accepted-table paths:
  `release-evidence-clean-host-final`,
  `os_mode_artifacts/clean-host-final-cache`,
  `release-evidence-clean-host-final.preflight.json`,
  `release-evidence-clean-host-final.acceptance.json`, and
  `release-evidence-clean-host-final.baseline.md`. The wrapper printed the
  expected preflight command, release-gate command with
  `--clean-host-baseline --preflight-json`, and acceptance command with
  `--artifact`; `ran=false`, so this was command-shape validation only and
  did not create the final clean Apple Silicon timing table.
- 2026-05-18 user-facing acceptance checklist doc sync:
  `README.md` and `examples/os_mode.md` now describe the same clean-host
  acceptance checklist contract as `examples/os_mode_clean_host_acceptance.py`,
  including `clean-host preflight`, `release-gate summary` strict-mode fields,
  and the requirement to regenerate archives collected before
  `image_was_explicit` was recorded.
- 2026-05-18 design-doc baseline snippet helper:
  added `examples/os_mode_design_doc_baseline.py` and
  `make os-mode-design-doc-baseline ACCEPTANCE_JSON=...`. The helper consumes
  accepted clean-host JSON, verifies `accepted=true`, verifies the strict
  requirement flags (`clean_cache`, `cache_entry_absent`, `apfs`,
  `macos_arm64`, `perf`, `clean_poweroff`, `clean_host_preflight`, and
  `build_provenance`, plus matching `artifact_manifest`/`artifact_load`), verifies the
  `required_checklist`/`evidence_checklist` order against the current
  acceptance contract, requires every checklist item to have passed, validates
  the baseline table columns, and prints the Markdown table plus replacement
  completion-audit row for `design_docs/full_linux_os_mode.md`.
  Host-independent checks cover the Python API, CLI, Make dry-run wrapper,
  rejected acceptance JSON, mutated strict requirements, and missing
  `release-gate summary` checklist item.
- 2026-05-18 current local rehearsal accepted under image-mode contract:
  reran `make os-mode-clean-host-baseline` against the durable Debian systemd
  artifact manifest with fresh paths
  `release-evidence-artifact-current-local9`,
  `os_mode_artifacts/current-local9-cache`, and
  `release-evidence-artifact-current-local9.preflight.json`.
  The run completed preflight, Docker archive load, bundle extraction, APFS
  clone, host-side libkrun/HVF smoke launch, perf launch, release-evidence
  collection, verifier, and strict clean-host acceptance. The accepted JSON is
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local9.acceptance.json`
  and the accepted table is
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local9.baseline.md`.
  Current summary binding is present: `image_was_explicit=false`,
  artifact-manifest path recorded, and preflight `release_gate_command`
  positionals are empty. Accepted timings were artifact load `917 ms`, export
  `1684 ms`, bundle extraction `8132 ms`, APFS clone `141 ms`, first boot log
  `148 ms`, root marker `883 ms`, PID 1 marker `885 ms`, ready marker
  `889 ms`, clean poweroff `yes`, and total `10261 ms`. This is current local
  rehearsal evidence on the development host, not the final clean Apple
  Silicon release-machine baseline.
  `make os-mode-design-doc-baseline
  ACCEPTANCE_JSON=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local9.acceptance.json
  EVIDENCE_LABEL=release-evidence-artifact-current-local9` passed and printed
  the design-doc table plus completion-audit row for this accepted local
  rehearsal.
  This archive is now historical because the acceptance contract was tightened
  again to require `build provenance`.
- 2026-05-18 build-provenance acceptance item:
  `examples/os_mode_clean_host_acceptance.py` now requires `build provenance`
  in the strict clean-host checklist. The item requires at least one
  caller-supplied build command and also requires the generated
  `artifact_load_command=...` and `smoke_importer_command=...` entries for
  artifact-delivered evidence. Host-independent checks cover the negative case
  where only generated commands are present. `README.md`,
  `examples/os_mode.md`, and `design_docs/full_linux_os_mode.md` now document
  this checklist item, and `examples/os_mode_design_doc_baseline.py` rejects
  accepted JSON whose checklist order does not match the current contract.
- 2026-05-18 current local rehearsal accepted under build-provenance contract:
  reran `make os-mode-clean-host-baseline` against the durable Debian systemd
  artifact manifest with fresh paths
  `release-evidence-artifact-current-local11`,
  `os_mode_artifacts/current-local11-cache`, and
  `release-evidence-artifact-current-local11.preflight.json`, passing
  `BUILD_COMMAND='PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang'`.
  The run completed preflight, Docker archive load, bundle extraction, APFS
  clone, host-side libkrun/HVF smoke launch, perf launch, release-evidence
  collection, verifier, strict clean-host acceptance, and design-doc baseline
  rendering. The original accepted JSON was
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11.acceptance.json`
  and the original accepted table was
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11.baseline.md`.
  Current summary binding is present: `image_was_explicit=false`,
  artifact-manifest path recorded, and preflight `release_gate_command`
  positionals are empty. Build provenance is present: one caller-supplied
  libkrun build command, one generated artifact-load command, and one
  generated smoke-import command. Accepted timings were artifact load
  `906 ms`, export `1684 ms`, bundle extraction `7814 ms`, APFS clone
  `107 ms`, first boot log `112 ms`, root marker `821 ms`, PID 1 marker
  `823 ms`, ready marker `826 ms`, clean poweroff `yes`, and total `9559 ms`.
  This is current local rehearsal evidence on the development host, not the
  final clean Apple Silicon release-machine baseline.
- 2026-05-18 archive verifier build-provenance gate:
  `examples/os_mode_verify_release_evidence.py` now accepts
  `--require-build-provenance`. The Make clean-host verifier target forwards
  this flag by default, clean-host acceptance uses it before building the
  acceptance checklist, and `examples/os_mode_release_gate.py` enables it for
  clean-host-preflight verification. The verifier requires a caller-supplied
  build command plus generated `artifact_load_command=...` and
  `smoke_importer_command=...` entries that decode to the same commands
  recorded in `release-gate-summary.json`. Host-independent checks now reject
  verifier evidence that contains only generated commands. A real archive
  recheck passed:
  `make os-mode-verify-release-evidence
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11
  ARTIFACT=1`, which invoked the verifier with
  `--require-build-provenance` and returned `verified=true`,
  `observed_pid1=systemd`, `observed_root=/dev/vda`, and
  `observed_console=[ttyAMA0]`.
- 2026-05-18 current local rehearsal re-accepted under verifier
  build-provenance contract:
  reran the clean-host acceptance helper against the existing
  `release-evidence-artifact-current-local11` archive after wiring
  `--require-build-provenance` into the verifier path:
  `make os-mode-accept-clean-host
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11
  ARTIFACT=1
  JSON_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11.strict.acceptance.json
  TABLE_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11.strict.baseline.md`.
  The strict acceptance JSON recorded `accepted=true`, `verification.verified=true`,
  `observed_pid1=systemd`, `observed_root=/dev/vda`, `observed_console=[ttyAMA0]`,
  and the ordered checklist including `build provenance`.
- 2026-05-18 current local rehearsal re-accepted with explicit
  build-provenance requirement flag:
  after adding `requirements.build_provenance=true` to clean-host acceptance
  JSON and requiring it in `examples/os_mode_design_doc_baseline.py`, reran
  acceptance as
  `make os-mode-accept-clean-host
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11
  ARTIFACT=1
  JSON_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11.strict2.acceptance.json
  TABLE_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local11.strict2.baseline.md`.
  The new JSON records `requirements.build_provenance=true` and remains the
  current local development-host acceptance artifact referenced by
  `design_docs/full_linux_os_mode.md`.
- 2026-05-18 design-doc baseline final-row safety:
  `examples/os_mode_design_doc_baseline.py` now prints the completion-audit
  row as `Open` by default and only prints `Implemented` when called with
  `--final-release-baseline` through `FINAL_RELEASE_BASELINE=1`. This keeps
  local rehearsal evidence from being accidentally pasted into the final clean
  Apple Silicon baseline row as completed. Host-independent checks cover the
  Python API, CLI, and Make wrapper behavior for both default rehearsal and
  explicit final-release modes.
- 2026-05-18 clean-host baseline design-doc snippet output:
  `examples/os_mode_clean_host_baseline.py` now accepts
  `--design-doc-output`, `--evidence-label`, and `--final-release-baseline`.
  When `--design-doc-output` is supplied with `--accept-json-output`, the
  wrapper runs the design-doc snippet helper after strict acceptance succeeds
  and writes the snippet to the requested path. The Make wrapper forwards
  `DESIGN_DOC_OUTPUT`, `EVIDENCE_LABEL`, and `FINAL_RELEASE_BASELINE=1`.
  Host-independent checks verify command construction, output-path collision
  rejection, the required `--accept-json-output` dependency, result reporting,
  and Make dry-run forwarding.
- 2026-05-18 clean-host baseline orphan design-doc option guard:
  `examples/os_mode_clean_host_baseline.py` now rejects `--evidence-label` or
  `--final-release-baseline` unless `--design-doc-output` is also supplied, so
  final-baseline labeling options cannot be silently ignored. Host-independent
  checks cover the rejection.
- 2026-05-18 Make wrapper design-doc option guard:
  `make os-mode-clean-host-baseline` now fails before invoking the Python
  wrapper when `EVIDENCE_LABEL` or `FINAL_RELEASE_BASELINE=1` is set without
  `DESIGN_DOC_OUTPUT`. Host-independent checks cover the Make-level error so
  users get a clear message before the clean-host command sequence starts.
- 2026-05-18 Make wrapper design-doc acceptance dependency guard:
  `make os-mode-clean-host-baseline` now also fails before invoking the Python
  wrapper when `DESIGN_DOC_OUTPUT` is set without `ACCEPT_JSON_OUTPUT`, because
  the design-doc snippet renderer consumes the accepted JSON. Host-independent
  checks cover the Make-level error.
- 2026-05-18 published artifact clean-host command templates:
  `examples/os_mode_publish_container_bundle.py` now writes
  `--design-doc-output DESIGN_DOC_SNIPPET_MD --evidence-label
  RELEASE_EVIDENCE_LABEL --final-release-baseline` into the
  `clean_host_baseline` and `clean_host_baseline_from_artifact` command
  templates in `libkrun.os-bundle.artifact.v1` manifests. Host-independent
  publisher tests check the exact generated commands. Existing archived
  evidence remains verifier-compatible; this is a forward-looking template
  improvement for newly published bundles.
- 2026-05-18 optional artifact design-doc template verification:
  `examples/os_mode_verify_release_evidence.py` remains compatible with older
  artifact manifests that do not include design-doc snippet output placeholders,
  but when any of the new placeholders are present it now requires the full
  `--design-doc-output DESIGN_DOC_SNIPPET_MD --evidence-label
  RELEASE_EVIDENCE_LABEL --final-release-baseline` set. Host-independent
  checks cover the partial-placeholder rejection.
- 2026-05-18 final clean-host runbook convergence:
  `design_docs/full_linux_os_mode.md` now makes `make
  os-mode-clean-host-baseline ... DESIGN_DOC_OUTPUT=...
  FINAL_RELEASE_BASELINE=1` the preferred final clean-host command. The older
  `make os-mode-accept-clean-host` plus `make os-mode-design-doc-baseline`
  sequence remains documented only as the lower-level path for an already
  archived run.
- 2026-05-18 clean-host baseline result path reporting:
  `examples/os_mode_clean_host_baseline.py` now reports the resolved
  `output_dir`, `preflight_json`, acceptance JSON/table outputs, and
  design-doc snippet output in its JSON result when those outputs are
  requested. Host-independent checks assert the reported paths so the final
  clean-host command output can be audited without reconstructing artifact
  locations from the original command line.
- 2026-05-18 macOS debug build recheck:
  `make debug BLK=1 NET=1` passes on the local Apple Silicon host after making
  Homebrew LLVM's `libclang.dylib` visible to bindgen build scripts through a
  local `target/debug/libclang.dylib` symlink and `LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib`.
  A direct `cargo check --features blk,net` is not the correct macOS build gate
  because it does not export the repo's Linux sysroot compiler settings for
  `init/init.c`.
- 2026-05-18 current local clean-host-wrapper rehearsal:
  ran `make os-mode-clean-host-baseline` with the archive artifact manifest,
  fresh `release-cache-current-local12`, fresh
  `release-evidence-artifact-current-local12`, build provenance command
  `LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib make debug BLK=1 NET=1`,
  accepted JSON/table outputs, and `DESIGN_DOC_OUTPUT`, but without
  `FINAL_RELEASE_BASELINE=1`. The wrapper ran preflight, artifact load,
  release gate, strict acceptance, and design-doc snippet rendering
  successfully. The accepted table records image load/pull/export
  `1123/-/1684 ms`, bundle extraction `8237 ms`, APFS clone `113 ms`, first
  log `110 ms`, root `806 ms`, PID 1 `812 ms`, ready `815 ms`, clean
  poweroff `yes`, and total `10010 ms`. The generated design-doc snippet keeps
  the completion-audit row `Open`, as intended for a development-host
  rehearsal.
- 2026-05-18 final-baseline acceptance attestation:
  `examples/os_mode_clean_host_acceptance.py` now records
  `final_release_baseline=false` by default and `true` only when called with
  `--final-release-baseline`; `examples/os_mode_clean_host_baseline.py` and
  the Make wrappers propagate that flag. `examples/os_mode_design_doc_baseline.py`
  now refuses to render an `Implemented` completion-audit row unless both the
  renderer flag and the accepted JSON attestation are present. Host-independent
  checks cover default-open rehearsal behavior, final-mode propagation through
  the one-shot wrapper and Make targets, rejection of non-final acceptance JSON
  for final rendering, and successful final rendering from final-attested
  acceptance JSON.
- 2026-05-18 current local rehearsal re-accepted with final-baseline
  attestation field:
  reran strict acceptance against
  `release-evidence-artifact-current-local12` as
  `make os-mode-accept-clean-host
  EVIDENCE_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12
  ARTIFACT=1
  JSON_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12.strict2.acceptance.json
  TABLE_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12.strict2.baseline.md`.
  The new accepted JSON records `final_release_baseline=false`, and the
  refreshed design-doc snippet remains `Open`.
- 2026-05-18 final-baseline acceptance JSON guard:
  `make os-mode-accept-clean-host` now rejects `FINAL_RELEASE_BASELINE=1`
  unless `JSON_OUTPUT` is also set, because the final-baseline attestation must
  be preserved in the accepted JSON consumed by
  `make os-mode-design-doc-baseline`. Host-independent checks cover the
  Make-level rejection and error text.
- 2026-05-18 durable local artifact command refresh:
  refreshed
  `os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json`
  so its `clean_host_baseline` and `clean_host_baseline_from_artifact`
  templates include `--design-doc-output DESIGN_DOC_SNIPPET_MD`,
  `--evidence-label RELEASE_EVIDENCE_LABEL`, and
  `--final-release-baseline`. Host-independent checks remain compatible with
  older artifact manifests, but now verify that any durable manifest command
  advertising design-doc output contains the complete placeholder set.
- 2026-05-18 final-baseline accepted table guard:
  `make os-mode-clean-host-baseline` now rejects
  `FINAL_RELEASE_BASELINE=1` unless `ACCEPT_TABLE_OUTPUT` is set, and
  `make os-mode-accept-clean-host` rejects `FINAL_RELEASE_BASELINE=1` unless
  `TABLE_OUTPUT` is set. This keeps the final accepted Markdown table as a
  standalone artifact alongside the accepted JSON and design-doc snippet.
  Host-independent checks cover both Make-level rejections and error text.
- 2026-05-18 direct CLI final-baseline output guards:
  `examples/os_mode_clean_host_baseline.py` now rejects
  `--final-release-baseline` unless `--accept-table-output` is set, and
  `examples/os_mode_clean_host_acceptance.py` rejects
  `--final-release-baseline` unless both `--json-output` and `--table-output`
  are set. This mirrors the Make wrapper safeguards for direct helper usage.
  Host-independent checks cover the Python API and CLI rejections.
- 2026-05-18 macOS build-command documentation alignment:
  updated the README, OS-mode example docs, and final clean-host runbook
  command to include `LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib` alongside the
  Homebrew LLVM/lld `PATH` and `CLANG` settings. This matches the local macOS
  build validation that required Homebrew `libclang.dylib` to be visible to
  bindgen build scripts.
- 2026-05-18 rehearsal versus final command wording:
  clarified in `README.md` and `examples/os_mode.md` that the short
  clean-host baseline examples produce rehearsal evidence unless
  `FINAL_RELEASE_BASELINE=1` and `EVIDENCE_LABEL` are supplied. The final mode
  wording now calls out the required accepted JSON, accepted Markdown table,
  and design-doc snippet outputs.
- 2026-05-18 prompt-to-artifact completion checklist:
  added a prompt-to-artifact checklist to
  `design_docs/full_linux_os_mode.md` mapping the user-requested deliverables
  to concrete files, commands, gates, and evidence. The checklist keeps the
  final release-ready baseline artifacts open until a genuinely clean Apple
  Silicon host produces accepted JSON, accepted Markdown, a design-doc snippet,
  and `final_release_baseline=true`.
- 2026-05-18 acceptance timestamp:
  `examples/os_mode_clean_host_acceptance.py` now records `accepted_at_utc` in
  accepted JSON output. Host-independent checks verify the UTC timestamp shape
  for both the Python API and CLI paths, and the README/design docs now list
  the timestamp as part of the accepted evidence artifact.
- 2026-05-18 design-doc snippet artifact output:
  `examples/os_mode_design_doc_baseline.py` now accepts `--output` and refuses
  missing-parent or pre-existing destinations before writing the rendered
  Markdown snippet. `examples/os_mode_clean_host_baseline.py` uses that direct
  output mode, and `make os-mode-design-doc-baseline` forwards
  `DESIGN_DOC_OUTPUT=...`. Host-independent checks cover stdout rendering,
  output-file rendering, existing-output rejection, Make forwarding, and the
  one-shot baseline wrapper command path.
- 2026-05-18 current local rehearsal re-accepted with timestamped schema:
  reran strict acceptance against
  `release-evidence-artifact-current-local12` as `strict3`, producing
  `release-evidence-artifact-current-local12.strict3.acceptance.json`,
  `release-evidence-artifact-current-local12.strict3.baseline.md`, and
  `release-evidence-artifact-current-local12.strict3.design-doc.md`. The
  accepted JSON records `accepted_at_utc=2026-05-18T23:01:50Z` and
  `final_release_baseline=false`, so the rehearsal design-doc row remains
  `Open`.
- 2026-05-18 final-baseline artifact-set audit:
  added `examples/os_mode_final_baseline_audit.py` and
  `make os-mode-audit-final-baseline` to verify the final release-ready
  artifact set as a group. The audit reruns strict acceptance using the
  delivery mode recorded in the accepted JSON, rejects non-final accepted JSON,
  and checks that the standalone accepted Markdown table and design-doc snippet
  match the final accepted JSON exactly. Host-independent checks cover the
  helper CLI, Make forwarding, success on synthetic final evidence, and
  rejection of non-final acceptance JSON, stale accepted tables, and stale
  design-doc snippets.
- 2026-05-19 final clean-host baseline:
  fixed `examples/os_mode_clean_host_baseline.py` by importing `subprocess`
  for the real run path, made `examples/os_mode_final_baseline_audit.py`
  executable so the Make target can invoke it directly, rebuilt libkrun with
  `KRUN_INIT_BINARY_PATH=/bin/echo
  LIBCLANG_PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib
  make BLK=1 NET=1`, and ran the archive-delivered final baseline:
  `make os-mode-clean-host-baseline ARTIFACT_MANIFEST=os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json
  OUTPUT_DIR=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b
  CACHE_DIR=os_mode_artifacts/final-clean-host-cache-20260519b
  PREFLIGHT_JSON=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.preflight.json
  ACCEPT_JSON_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.acceptance.json
  ACCEPT_TABLE_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.baseline.md
  DESIGN_DOC_OUTPUT=os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.design-doc.md
  EVIDENCE_LABEL=release-evidence-artifact-final-clean-host-20260519b
  FINAL_RELEASE_BASELINE=1
  BUILD_COMMAND='KRUN_INIT_BINARY_PATH=/bin/echo
  LIBCLANG_PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib
  make BLK=1 NET=1'`.
  Preflight proved the derived cache entry and release-evidence output were
  absent and on APFS. The release gate loaded the durable archive, extracted
  the bundle, APFS-cloned `root.raw`, launched host-side `examples/os_mode`
  under HVF, observed root `/dev/vda`, PID 1 `systemd`, console `ttyAMA0`,
  readiness, and clean poweroff, then strict acceptance wrote final JSON,
  Markdown, and design-doc snippet artifacts with
  `final_release_baseline=true`.
  The accepted baseline row is image load/pull/export `2692/-/1684 ms`,
  bundle extraction `4595 ms`, APFS clone `245 ms`, first log `472 ms`, root
  marker `612 ms`, PID 1 marker `614 ms`, ready marker `617 ms`, clean
  poweroff `yes`, total `6500 ms`. A follow-up
  `make os-mode-audit-final-baseline` run passed for the accepted JSON,
  accepted table, design-doc snippet, and evidence directory with
  `required_check_count=18`.
