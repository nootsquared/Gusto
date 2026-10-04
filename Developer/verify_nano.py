import argparse
import json
import math
import re
import time
import unittest
from pathlib import Path


def parse_data(line):
    fields = line.rstrip('\r\n').split(',')
    if len(fields) != 8 or fields[:2] != ['DATA', '1']:
        raise ValueError('Invalid record shape or version')
    integers = []
    for field in (fields[2], fields[3], fields[7]):
        if not re.fullmatch(r'[0-9]+', field):
            raise ValueError('Invalid unsigned integer')
        integers.append(int(field))
    sequence, uptime, mask = integers
    if sequence > 0xffffffff or uptime > 0xffffffff or mask > 7:
        raise ValueError('Integer overflow')
    values = []
    for index, (low, high) in enumerate(((-40, 185), (0, 100), (0, 65535))):
        field = fields[4 + index]
        valid = bool(mask & (1 << index))
        if not valid:
            if field != 'NA':
                raise ValueError('Invalid field must be NA')
            values.append(None)
            continue
        if not re.fullmatch(r'-?[0-9]+\.[0-9]', field) if index < 2 else not re.fullmatch(r'[0-9]+', field):
            raise ValueError('Invalid numeric format')
        value = float(field) if index < 2 else int(field)
        if not math.isfinite(value) or not low <= value <= high:
            raise ValueError('Invalid numeric value')
        values.append(value)
    return dict(sequence=sequence, uptime_ms=uptime, temperature_f=values[0],
                humidity_percent=values[1], light_counts=values[2], valid_mask=mask)


class ProtocolTests(unittest.TestCase):
    def test_valid_and_crlf(self):
        for ending in ('\n', '\r\n'):
            self.assertEqual(parse_data('DATA,1,42,1000,72.5,45.0,320,7' + ending)['valid_mask'], 7)

    def test_boundaries_and_wrap(self):
        sample = parse_data('DATA,1,4294967295,4294967295,-40.0,100.0,65535,7')
        self.assertEqual(sample['sequence'], 0xffffffff)
        self.assertEqual(parse_data('DATA,1,0,0,185.0,0.0,0,7')['sequence'], 0)

    def test_missing_fields(self):
        self.assertIsNone(parse_data('DATA,1,0,0,NA,NA,NA,0')['temperature_f'])

    def test_invalid(self):
        valid = 'DATA,1,1,1000,72.5,45.0,320,7'
        cases = [valid.replace('DATA,1', 'DATA,2'), valid + ',extra',
                 valid.replace('72.5', 'nan'), valid.replace('72.5', 'inf'),
                 valid.replace('72.5', 'NA'), valid.replace('45.0', '100.1'),
                 valid.replace('320', '65536'), valid.replace(',7', ',0'),
                 valid.replace(',1,1000', ',4294967296,1000')]
        for line in cases:
            with self.subTest(line=line), self.assertRaises(ValueError):
                parse_data(line)


def verify_nano(port, output):
    import serial
    samples = []
    nonce = 'usb_' + str(time.time_ns())
    pong = False
    with serial.Serial(port, 115200, timeout=0.25, write_timeout=2) as device:
        time.sleep(2)
        device.reset_input_buffer()
        device.write(('PING,1,' + nonce + '\n').encode('ascii'))
        started = time.monotonic()
        pending = bytearray()
        while time.monotonic() - started < 20:
            raw = device.read_until(b'\n', 128 - len(pending))
            pending.extend(raw)
            if len(pending) >= 128:
                raise ValueError('Oversized record')
            if not pending.endswith(b'\n'):
                continue
            line = pending.decode('ascii').strip()
            pending.clear()
            print(line)
            if line == 'PONG,1,' + nonce:
                pong = True
            elif line.startswith('DATA,'):
                sample = parse_data(line)
                if samples and sample['sequence'] != (samples[-1]['sequence'] + 1) & 0xffffffff:
                    raise ValueError('Sequence failed to advance')
                samples.append(sample)
            if not pong and time.monotonic() - started > 2:
                raise ValueError('USB ping timed out')
            if pong and len(samples) >= 10:
                break
    if not pong or len(samples) < 10 or any(s['valid_mask'] != 7 for s in samples):
        raise ValueError('Sensor or USB verification failed')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dict(usb_ping_passed=pong, samples=samples), indent=2))
    print('PASS: USB ping and ten complete sensor records. Physical UART is not verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--port')
    parser.add_argument('--output', type=Path, default=Path('nano-verification.json'))
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=['verify_nano.py'])
    elif args.port:
        verify_nano(args.port, args.output)
    else:
        parser.error('Use --self-test or --port COMx; hardware mode requires pyserial.')
