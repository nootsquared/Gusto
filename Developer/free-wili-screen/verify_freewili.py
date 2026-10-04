import argparse
import datetime
import json
import re
import time
from pathlib import Path

import serial


def fields(line):
    return dict(re.findall(r"(\w+)=([^\s]+)", line))


def verify(port, standalone, seconds, output):
    evidence = []
    samples = []
    acknowledgments = set()
    matched_pongs = set()
    status = None
    sent = set()
    run_id = str(time.time_ns())
    with serial.Serial(port, 115200, timeout=0.2, write_timeout=2) as device:
        time.sleep(1)
        device.reset_input_buffer()
        device.write(b"status\n")
        started = time.monotonic()
        for index in range(10 if not standalone else 1):
            nonce = f"p{index}_{run_id}"
            sent.add(nonce)
            device.write(f"ping {nonce}\n".encode("ascii"))
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                line = device.readline().decode("utf-8", "replace").strip()
                if not line:
                    continue
                evidence.append(line)
                print(line)
                if line.startswith("STATUS "):
                    status = fields(line)
                elif line.startswith("SAMPLE "):
                    samples.append(fields(line))
                elif line.startswith("DISPLAY_ACK "):
                    acknowledgments.add(int(fields(line)["sequence"]))
                elif line.startswith("UART_PONG "):
                    matched_pongs.add(line.split()[1])
                    if line.split()[1] == nonce:
                        break
                elif line == f"PING_TIMEOUT {nonce}" and standalone:
                    break
            if not standalone and nonce not in matched_pongs:
                raise RuntimeError(f"Physical UART ping did not return: {nonce}")
        while not standalone and time.monotonic() - started < seconds:
            line = device.readline().decode("utf-8", "replace").strip()
            if not line:
                continue
            evidence.append(line)
            print(line)
            if line.startswith("SAMPLE "):
                samples.append(fields(line))
            elif line.startswith("DISPLAY_ACK "):
                acknowledgments.add(int(fields(line)["sequence"]))
        device.write(b"status\n")
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            line = device.readline().decode("utf-8", "replace").strip()
            if line:
                evidence.append(line)
                print(line)
                if line.startswith("STATUS "):
                    status = fields(line)
    if not status or status.get("uart_ready") != "1" or status.get("directions_complete") != "1":
        raise RuntimeError("External UART direction configuration was not confirmed")
    if standalone:
        if matched_pongs or not any(line.startswith("PING_TIMEOUT ") for line in evidence):
            raise RuntimeError("Expected timeout with Nano disconnected")
    else:
        if len(matched_pongs & sent) != 10 or len(samples) < 25:
            raise RuntimeError("Insufficient ping or telemetry evidence")
        sequences = [int(sample["sequence"]) for sample in samples]
        if any(current != ((previous + 1) & 0xffffffff) for previous, current in zip(sequences, sequences[1:])):
            raise RuntimeError("Sample sequences are discontinuous")
        if any(sample["valid_mask"] != "7" for sample in samples):
            raise RuntimeError("One or more sensors reported invalid readings")
        if len(acknowledgments.intersection(sequences)) < len(samples) - 1:
            raise RuntimeError("Display acknowledgments did not follow received samples")
    report = dict(timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  port=port, standalone=standalone, status=status,
                  uart_ping_count=len(matched_pongs & sent), samples=samples,
                  display_ack_sequences=sorted(acknowledgments), evidence=evidence,
                  lcd_visual_check="pending", calibrated_accuracy="not_verified")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("PASS: standalone UART configuration and expected disconnected ping timeout" if standalone
          else "PASS: ten physical UART pings, live telemetry and display acknowledgments")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--standalone", action="store_true")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.standalone and args.seconds < 30:
        parser.error("Connected verification requires at least 30 seconds")
    verify(args.port, args.standalone, args.seconds, args.output)
