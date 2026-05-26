#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time


REQUIRED_MARKERS = (
    "KRUN_OSMODE: init-started",
    "KRUN_OSMODE: root=",
    "KRUN_OSMODE: pid1=",
    "KRUN_OSMODE: console=",
    "KRUN_OSMODE: ready",
)

TIMING_MARKERS = {
    "init_start_ms": "KRUN_OSMODE: init-started",
    "root_ms": "KRUN_OSMODE: root=",
    "pid1_ms": "KRUN_OSMODE: pid1=",
    "console_ms": "KRUN_OSMODE: console=",
    "ready_ms": "KRUN_OSMODE: ready",
}

EARLY_KERNEL_MARKERS = (
    "Booting Linux",
    "Linux version",
    "Kernel command line",
)


def is_kernel_timestamp_line(line):
    if not line.startswith("["):
        return False
    end = line.find("]")
    if end <= 1:
        return False
    timestamp = line[1:end].strip()
    seconds, dot, fraction = timestamp.partition(".")
    return bool(dot) and seconds.isdigit() and fraction.isdigit()


def is_early_kernel_line(line):
    return is_kernel_timestamp_line(line) and any(marker in line for marker in EARLY_KERNEL_MARKERS)


def normalized_os_marker(line):
    marker_start = line.find("KRUN_OSMODE:")
    if marker_start == -1:
        return None
    return line[marker_start:]


def positive_float(value):
    try:
        parsed = float(value)
    except ValueError as err:
        raise argparse.ArgumentTypeError("value must be a number") from err
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be greater than zero")
    return parsed


def non_negative_float(value):
    try:
        parsed = float(value)
    except ValueError as err:
        raise argparse.ArgumentTypeError("value must be a number") from err
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be non-negative")
    return parsed


def non_empty_arg(value):
    if value == "":
        raise argparse.ArgumentTypeError("value must be non-empty")
    return value


def existing_output_error(path):
    output = Path(path).expanduser()
    if not output.parent.is_dir():
        return f"--output parent directory does not exist: {output.parent}"
    if output.exists():
        return "--output destination already exists"
    return None


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run examples/os_mode and wait for OS-mode readiness markers."
    )
    parser.add_argument("--timeout", type=positive_float, default=30.0)
    parser.add_argument(
        "--wait-exit-after-ready",
        type=non_negative_float,
        default=None,
        help=(
            "After all readiness markers are observed, wait this many seconds "
            "for the VMM process to exit and fail on timeout or nonzero exit."
        ),
    )
    parser.add_argument("--expect-root", type=non_empty_arg, default=None)
    parser.add_argument("--expect-console", type=non_empty_arg, default=None)
    parser.add_argument("--expect-pid1", type=non_empty_arg, default=None)
    parser.add_argument(
        "--expect-marker",
        action="append",
        type=non_empty_arg,
        default=[],
        help=(
            "Additional output marker substring that must appear before the "
            "smoke test succeeds. May be passed more than once."
        ),
    )
    parser.add_argument(
        "--output",
        type=non_empty_arg,
        default=None,
        help=(
            "Optional JSON file that records merged stdout/stderr, elapsed "
            "time, exit status, and markers."
        ),
    )
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        parser.error("missing os_mode command after --")
    if args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("missing os_mode command after --")
    if args.output:
        output_error = existing_output_error(args.output)
        if output_error is not None:
            parser.error(output_error)
    return args


def main():
    args = parse_args()
    started = time.monotonic()
    seen = set()
    expected_seen = set()
    lines = []
    deadline = time.monotonic() + args.timeout
    failure_reason = None
    timed_out = False
    success = False
    observed = {}
    timings = {}

    proc = subprocess.Popen(
        args.command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)

    try:
        output_buffer = ""

        def process_line(line):
            nonlocal failure_reason

            now_ms = int((time.monotonic() - started) * 1000)
            line = line.rstrip("\r")
            lines.append(line)
            marker_line = normalized_os_marker(line)
            if "first_kernel_log_ms" not in timings and is_early_kernel_line(line):
                timings["first_kernel_log_ms"] = now_ms
            for marker in REQUIRED_MARKERS:
                if marker_line is not None and marker_line.startswith(marker):
                    seen.add(marker)
            if marker_line is not None:
                for key, marker in TIMING_MARKERS.items():
                    if key not in timings and marker_line.startswith(marker):
                        timings[key] = now_ms
            for marker in args.expect_marker:
                if marker in line:
                    expected_seen.add(marker)

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: root="):
                root_payload = marker_line.removeprefix("KRUN_OSMODE: root=")
                root_source = root_payload.split(maxsplit=1)[0] if root_payload else ""
                observed["root"] = root_source
                observed["root_line"] = root_payload
                if not root_source:
                    print("root marker did not include a source token", file=sys.stderr)
                    failure_reason = "root-missing"
                    return False
                if args.expect_root and root_source != args.expect_root:
                    print(
                        f"root marker source {root_source!r} does not match expected value {args.expect_root!r}",
                        file=sys.stderr,
                    )
                    failure_reason = "root-mismatch"
                    return False

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: pid1="):
                pid1_payload = marker_line.removeprefix("KRUN_OSMODE: pid1=")
                pid1 = pid1_payload.split(maxsplit=1)[0] if pid1_payload else ""
                observed["pid1"] = pid1
                observed["pid1_line"] = pid1_payload
                if not pid1:
                    print("pid1 marker did not include a process name", file=sys.stderr)
                    failure_reason = "pid1-missing"
                    return False
                if "init.krun" in marker_line:
                    print("pid1 marker identifies init.krun, not the guest OS init", file=sys.stderr)
                    failure_reason = "pid1-init.krun"
                    return False
                if args.expect_pid1 and pid1 != args.expect_pid1:
                    print(
                        f"pid1 marker {pid1!r} does not match expected value {args.expect_pid1!r}",
                        file=sys.stderr,
                    )
                    failure_reason = "pid1-mismatch"
                    return False

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: console="):
                consoles = marker_line.removeprefix("KRUN_OSMODE: console=").split()
                observed["consoles"] = consoles
                observed["console"] = consoles[0] if consoles else ""
                if not consoles:
                    print("console marker did not include an active console", file=sys.stderr)
                    failure_reason = "console-missing"
                    return False
                if args.expect_console and args.expect_console not in consoles:
                    print(
                        f"console marker {consoles!r} does not include expected console {args.expect_console!r}",
                        file=sys.stderr,
                    )
                    failure_reason = "console-mismatch"
                    return False

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: network="):
                observed["network"] = marker_line.removeprefix("KRUN_OSMODE: network=")

            return True

        def markers_complete():
            return (
                all(marker in seen for marker in REQUIRED_MARKERS)
                and all(marker in expected_seen for marker in args.expect_marker)
            )

        def read_ready_output_until(wait_deadline, stop_at_markers=True):
            nonlocal output_buffer, failure_reason, success, timed_out

            while time.monotonic() < wait_deadline:
                events = selector.select(
                    timeout=min(0.05, max(0.0, wait_deadline - time.monotonic()))
                )
                if not events:
                    if proc.poll() is not None:
                        return
                    continue

                try:
                    chunk = os.read(proc.stdout.fileno(), 4096)
                except BlockingIOError:
                    continue

                if not chunk:
                    if proc.poll() is not None:
                        return
                    continue

                text = chunk.decode("utf-8", errors="replace")
                sys.stdout.write(text)
                sys.stdout.flush()
                output_buffer += text
                while "\n" in output_buffer:
                    line, output_buffer = output_buffer.split("\n", 1)
                    if not process_line(line):
                        return
                if failure_reason:
                    return

                if stop_at_markers and markers_complete():
                    success = True
                    return

        while time.monotonic() < deadline:
            events = selector.select(timeout=min(0.05, max(0.0, deadline - time.monotonic())))
            if not events:
                if proc.poll() is not None:
                    break
                continue

            try:
                chunk = os.read(proc.stdout.fileno(), 4096)
            except BlockingIOError:
                continue

            if not chunk:
                if proc.poll() is not None:
                    break
                continue

            text = chunk.decode("utf-8", errors="replace")
            sys.stdout.write(text)
            sys.stdout.flush()
            output_buffer += text
            while "\n" in output_buffer:
                line, output_buffer = output_buffer.split("\n", 1)
                if not process_line(line):
                    break
            if failure_reason:
                break

            if markers_complete():
                success = True
                break

        if output_buffer and not failure_reason:
            if not process_line(output_buffer):
                success = False
            elif markers_complete():
                success = True
            output_buffer = ""

        if success and args.wait_exit_after_ready is not None and not failure_reason:
            exit_deadline = time.monotonic() + args.wait_exit_after_ready
            read_ready_output_until(exit_deadline, stop_at_markers=False)
            if output_buffer and not failure_reason:
                process_line(output_buffer)
                output_buffer = ""
            if not failure_reason:
                if proc.poll() is None:
                    timed_out = True
                    success = False
                    failure_reason = "exit-timeout"
                    print("VMM did not exit after readiness before timeout", file=sys.stderr)
                elif proc.returncode != 0:
                    success = False
                    failure_reason = "exit-nonzero"
                    print(f"VMM exited with status {proc.returncode}", file=sys.stderr)

        if not success and not failure_reason:
            missing_required = [marker for marker in REQUIRED_MARKERS if marker not in seen]
            missing_expected = [
                marker for marker in args.expect_marker if marker not in expected_seen
            ]
            missing = missing_required + missing_expected
            timed_out = proc.poll() is None
            failure_reason = (
                "missing-expected-markers"
                if not missing_required and missing_expected
                else "missing-markers"
            )
            print(f"missing readiness markers before timeout: {missing}", file=sys.stderr)
    finally:
        selector.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

    result = {
        "command": args.command,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "exit_code": proc.returncode,
        "expected_markers_seen": sorted(expected_seen),
        "failure_reason": failure_reason,
        "expected_pid1": args.expect_pid1,
        "launcher_pid": os.getpid(),
        "markers_seen": sorted(seen),
        "missing_markers": [
            marker for marker in REQUIRED_MARKERS if marker not in seen
        ] + [
            marker for marker in args.expect_marker if marker not in expected_seen
        ],
        "output_lines": lines,
        "observed": observed,
        "observed_console": observed.get("console"),
        "observed_consoles": observed.get("consoles"),
        "observed_network": observed.get("network"),
        "observed_pid1": observed.get("pid1"),
        "observed_pid1_line": observed.get("pid1_line"),
        "observed_root": observed.get("root"),
        "observed_root_line": observed.get("root_line"),
        "process_parent_pid": os.getpid(),
        "process_pid": proc.pid,
        "ready": success,
        "timings": timings,
        "timed_out": timed_out,
        "wait_exit_after_ready_sec": args.wait_exit_after_ready,
    }
    if args.output:
        with open(args.output, "x", encoding="utf-8") as f:
            json.dump(result, f, indent=2, sort_keys=True)
            f.write("\n")

    return 0 if success and failure_reason is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
