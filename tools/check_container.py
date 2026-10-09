#!/usr/bin/env python3
"""Build the host image and verify TLS play plus recovery in disposable containers."""
from pathlib import Path
import hashlib
import json
import re
import socket
import ssl
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = int(re.search(r'^  PROTOCOL = (\d+)$', (ROOT / 'lib/burrow.rb').read_text(), re.M).group(1))


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def connect(port, token=None):
    deadline = time.monotonic() + 20
    while True:
        try:
            tcp = socket.create_connection(('127.0.0.1', port), timeout=4)
            stream = ssl._create_unverified_context().wrap_socket(tcp, server_hostname='localhost')
            break
        except (OSError, ssl.SSLError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.2)
    fingerprint = hashlib.sha256(stream.getpeercert(binary_form=True)).hexdigest()
    wire = stream.makefile('rwb', buffering=64 * 1024)
    send(wire, {'type': 'hello', 'version': PROTOCOL, 'name': 'Container test', 'token': token})
    welcome = read(wire, lambda m: m['type'] == 'welcome')
    return stream, wire, welcome, fingerprint


def send(wire, message):
    wire.write((json.dumps(message) + '\n').encode())
    wire.flush()


def read(wire, predicate):
    while True:
        line = wire.readline(524288)
        assert line, 'Server disconnected'
        message = json.loads(line)
        assert message['type'] not in ('fatal', 'error'), message
        if predicate(message):
            return message


def main():
    subprocess.run(['docker', 'build', '-t', 'burrow-brigade:validation', '.'], cwd=ROOT, check=True)
    name = 'burrow-validation-' + uuid.uuid4().hex[:10]
    volume = name + '-data'
    run('docker', 'volume', 'create', volume)
    try:
        run('docker', 'run', '-d', '--name', name, '--read-only', '--cap-drop=ALL',
            '--security-opt=no-new-privileges:true', '--tmpfs', '/tmp:size=16m,mode=1777',
            '-p', '127.0.0.1::4388', '-v', volume + ':/var/lib/burrow', 'burrow-brigade:validation')
        port = int(run('docker', 'port', name, '4388/tcp').rsplit(':', 1)[1])
        stream, wire, welcome, pin = connect(port)
        send(wire, {'type': 'create', 'seq': 1, 'name': 'Container room', 'bots': 5, 'config': {'worms': 6}})
        state = read(wire, lambda m: m['type'] == 'state' and m.get('room'))
        code = state['room']['code']
        send(wire, {'type': 'start', 'seq': 2})
        state = read(wire, lambda m: m['type'] == 'state' and m.get('match'))
        assert len(state['match']['worms']) == 36
        send(wire, {'type': 'fire', 'seq': 3, 'weapon': 'grenade', 'fuse': 5, 'angle': -90, 'power': .6})
        flight = read(wire, lambda m: m['type'] == 'state' and m.get('match', {}).get('projectiles'))
        print(json.dumps({'flight_tick': flight['match']['tick'], 'projectiles': flight['match']['projectiles']}), flush=True)
        wire.close()
        stream.close()  # With no human connected, the in-flight match pauses.
        run('docker', 'exec', name, 'ruby', 'bin/healthcheck')
        restart_at = time.monotonic()
        run('docker', 'restart', '--time', '15', name)
        print('Restart seconds:', round(time.monotonic() - restart_at, 3), flush=True)
        # Docker may allocate a new ephemeral host port when restarting.
        port = int(run('docker', 'port', name, '4388/tcp').rsplit(':', 1)[1])
        stream, wire, resumed, recovered_pin = connect(port, welcome['token'])
        state = read(wire, lambda m: m['type'] == 'state' and m.get('match'))
        print(json.dumps({'recovered_tick': state['match']['tick'], 'projectiles': state['match']['projectiles']}), flush=True)
        assert resumed['id'] == welcome['id']
        assert recovered_pin == pin
        assert state['room']['code'] == code
        assert len(state['match']['worms']) == 36
        assert state['match']['tick'] >= flight['match']['tick']
        assert state['match']['projectiles'][0]['id'] == flight['match']['projectiles'][0]['id']
        run('docker', 'exec', name, 'ruby', 'bin/healthcheck')
        wire.close()
        stream.close()
        result = {'tls': True, 'teams': 6, 'grubs': 36, 'container_restart_recovered': True,
                  'session_preserved': True, 'certificate_preserved': True, 'healthcheck': True}
        path = ROOT / 'docs/validation/container.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
    except Exception:
        subprocess.run(['docker', 'logs', '--tail', '60', name], check=False)
        raise
    finally:
        subprocess.run(['docker', 'rm', '-f', name], check=False, stdout=subprocess.DEVNULL)
        subprocess.run(['docker', 'volume', 'rm', volume], check=False, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
