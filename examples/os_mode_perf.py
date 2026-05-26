#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time


PREFIX_MARKERS = {
    "first_kernel_log_ms": "[",
    "init_start_ms": "KRUN_OSMODE: init-started",
    "root_ms": "KRUN_OSMODE: root=",
    "pid1_ms": "KRUN_OSMODE: pid1=",
    "console_ms": "KRUN_OSMODE: console=",
    "write_ms": "KRUN_OSMODE: write=ok",
    "journald_ms": "KRUN_OSMODE: journald=ok",
    "package_manager_ms": "KRUN_OSMODE: package-manager=apt-update-ok",
    "ready_ms": "KRUN_OSMODE: ready",
}

SUBSTRING_MARKERS = {
    "root_mount_ms": "Mounting root: ok",
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


def marker_in_line(line, marker):
    if marker.startswith("KRUN_OSMODE:"):
        return marker in line
    return line.startswith(marker)


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


def nonnegative_float(value):
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


def output_path_error(path):
    output = Path(path).expanduser()
    if not output.parent.is_dir():
        return f"--output parent directory does not exist: {output.parent}"
    if output.exists():
        return "--output destination already exists"
    return None


def parse_args():
    parser = argparse.ArgumentParser(
        description="Measure an OS-mode boot command using KRUN_OSMODE markers."
    )
    parser.add_argument("--timeout", type=positive_float, default=60.0)
    parser.add_argument("--label", type=non_empty_arg, default="os-mode")
    parser.add_argument("--output", type=non_empty_arg, default=None)
    parser.add_argument(
        "--expect-root",
        type=non_empty_arg,
        default=None,
        help="Fail if the KRUN_OSMODE root marker reports a different source token.",
    )
    parser.add_argument(
        "--expect-console",
        type=non_empty_arg,
        default=None,
        help="Fail if the KRUN_OSMODE console marker does not include this console.",
    )
    parser.add_argument(
        "--require-pid1-marker",
        action="store_true",
        help="Fail unless a KRUN_OSMODE pid1 marker appears.",
    )
    parser.add_argument(
        "--shutdown-command",
        type=non_empty_arg,
        default=None,
        help="Command to send to guest stdin after the ready marker, for example 'poweroff -f'.",
    )
    parser.add_argument(
        "--control-command",
        action="append",
        type=non_empty_arg,
        default=[],
        help=(
            "Command to send to guest stdin after the ready marker. May be "
            "passed more than once."
        ),
    )
    parser.add_argument(
        "--expect-control-marker",
        type=non_empty_arg,
        default=None,
        help="Marker expected in guest output after --control-command is sent.",
    )
    parser.add_argument(
        "--control-delay",
        type=nonnegative_float,
        default=1.0,
        help="Seconds to wait after the ready marker before sending control commands.",
    )
    parser.add_argument(
        "--wait-exit-after-ready",
        type=nonnegative_float,
        default=0.0,
        help="After the ready marker, wait this many seconds for the VMM process to exit.",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        parser.error("missing command after --")
    if args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("missing command after --")
    if args.output:
        error = output_path_error(args.output)
        if error is not None:
            parser.error(error)
    return args


def main():
    args = parse_args()
    started = time.monotonic()
    deadline = started + args.timeout
    timings = {}
    lines = []
    observed = {}
    ready_at = None
    failure_reason = None

    proc = subprocess.Popen(
        args.command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=subprocess.PIPE if args.shutdown_command or args.control_command else None,
    )

    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)

    try:
        sent_control = False
        saw_control_marker = args.expect_control_marker is None
        sent_shutdown = False
        output_buffer = ""

        def process_line(line):
            nonlocal failure_reason, ready_at, saw_control_marker

            now_ms = int((time.monotonic() - started) * 1000)
            line = line.rstrip("\r")
            lines.append(line)
            marker_line = normalized_os_marker(line)

            for key, marker in PREFIX_MARKERS.items():
                if key == "first_kernel_log_ms":
                    matched = is_early_kernel_line(line)
                else:
                    matched = marker_in_line(line, marker)
                if key not in timings and matched:
                    timings[key] = now_ms
                    if key == "ready_ms":
                        ready_at = time.monotonic()
            for key, marker in SUBSTRING_MARKERS.items():
                if key not in timings and marker in line:
                    timings[key] = now_ms

            if (
                args.expect_control_marker
                and args.expect_control_marker in line
                and "control_ms" not in timings
            ):
                timings["control_ms"] = now_ms
                saw_control_marker = True

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: root="):
                root_payload = marker_line.removeprefix("KRUN_OSMODE: root=")
                root_source = root_payload.split(maxsplit=1)[0] if root_payload else ""
                observed["root"] = root_source
                observed["root_line"] = root_payload
                if args.expect_root and root_source != args.expect_root:
                    print(
                        f"root marker source {root_source!r} does not match expected value {args.expect_root!r}",
                        file=sys.stderr,
                    )
                    failure_reason = "root-mismatch"

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: pid1="):
                pid1_payload = marker_line.removeprefix("KRUN_OSMODE: pid1=")
                pid1 = pid1_payload.split(maxsplit=1)[0] if pid1_payload else ""
                observed["pid1"] = pid1
                observed["pid1_line"] = pid1_payload
                if args.require_pid1_marker and not pid1:
                    print("pid1 marker did not include a process name", file=sys.stderr)
                    failure_reason = "pid1-missing"
                elif "init.krun" in marker_line:
                    print("pid1 marker identifies init.krun, not the guest OS init", file=sys.stderr)
                    failure_reason = "pid1-init.krun"

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: console="):
                consoles = marker_line.removeprefix("KRUN_OSMODE: console=").split()
                observed["consoles"] = consoles
                observed["console"] = consoles[0] if consoles else ""
                if args.expect_console and args.expect_console not in consoles:
                    print(
                        f"console marker {consoles!r} does not include expected console {args.expect_console!r}",
                        file=sys.stderr,
                    )
                    failure_reason = "console-mismatch"

            if marker_line is not None and marker_line.startswith("KRUN_OSMODE: network="):
                observed["network"] = marker_line.removeprefix("KRUN_OSMODE: network=")

        def send_guest_command(command):
            proc.stdin.write((command + "\n").encode("utf-8"))
            proc.stdin.flush()

        def maybe_drive_ready_state():
            nonlocal failure_reason, sent_control, sent_shutdown

            if "ready_ms" not in timings:
                return False
            if (
                args.control_command
                and not sent_control
                and ready_at is not None
                and time.monotonic() >= ready_at + args.control_delay
            ):
                for command in args.control_command:
                    send_guest_command(command)
                sent_control = True
            if (
                args.shutdown_command
                and not sent_shutdown
                and (not args.control_command or saw_control_marker)
            ):
                send_guest_command(args.shutdown_command)
                sent_shutdown = True
            if args.wait_exit_after_ready > 0 and (
                not args.expect_control_marker or saw_control_marker
            ):
                exit_deadline = time.monotonic() + args.wait_exit_after_ready
                while time.monotonic() < exit_deadline:
                    if proc.poll() is not None:
                        break
                    time.sleep(0.05)
                if proc.poll() is None:
                    failure_reason = "exit-timeout"
                elif proc.returncode != 0:
                    failure_reason = "exit-nonzero"
                return True
            if (
                not args.shutdown_command
                and not args.control_command
                and not args.expect_control_marker
            ):
                return True
            if (
                args.control_command
                and not args.expect_control_marker
                and not args.shutdown_command
                and args.wait_exit_after_ready <= 0
                and sent_control
            ):
                return True
            if (
                args.expect_control_marker
                and saw_control_marker
                and not args.shutdown_command
                and args.wait_exit_after_ready <= 0
            ):
                return True
            return False

        while time.monotonic() < deadline:
            events = selector.select(timeout=min(0.05, max(0.0, deadline - time.monotonic())))
            if not events:
                if proc.poll() is not None:
                    break
                if maybe_drive_ready_state():
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
                process_line(line)

            if failure_reason:
                break
            if maybe_drive_ready_state():
                break
        if output_buffer:
            process_line(output_buffer)
    finally:
        selector.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

    if failure_reason is None:
        if args.expect_root and "root_ms" not in timings:
            failure_reason = "missing-root-marker"
        elif args.expect_console and "console_ms" not in timings:
            failure_reason = "missing-console-marker"
        elif args.require_pid1_marker and "pid1_ms" not in timings:
            failure_reason = "missing-pid1-marker"
        elif "ready_ms" not in timings:
            failure_reason = "missing-ready"
        elif not saw_control_marker:
            failure_reason = "missing-control-marker"

    result = {
        "label": args.label,
        "command": args.command,
        "exit_code": proc.returncode,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "expected_console": args.expect_console,
        "expected_root": args.expect_root,
        "failure_reason": failure_reason,
        "observed": observed,
        "observed_console": observed.get("console"),
        "observed_consoles": observed.get("consoles"),
        "observed_network": observed.get("network"),
        "observed_pid1": observed.get("pid1"),
        "observed_pid1_line": observed.get("pid1_line"),
        "observed_root": observed.get("root"),
        "observed_root_line": observed.get("root_line"),
        "output_lines": lines,
        "require_pid1_marker": args.require_pid1_marker,
        "timings": timings,
        "markers_seen": [
            marker for line in lines if (marker := normalized_os_marker(line)) is not None
        ],
    }

    if args.output:
        with open(args.output, "x", encoding="utf-8") as f:
            json.dump(result, f, indent=2, sort_keys=True)
            f.write("\n")
    else:
        print(json.dumps(result, indent=2, sort_keys=True))

    return 0 if "ready_ms" in timings and saw_control_marker and failure_reason is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
