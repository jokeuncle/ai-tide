#!/usr/bin/env python3
"""Verify the production nettop parser using an actual controlled 2 MiB loopback transfer."""
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
server_code = '''import socket,sys
s=socket.socket();s.bind(('127.0.0.1',0));s.listen();print(s.getsockname()[1],flush=True)
c,a=s.accept();print('ready',flush=True)
for line in sys.stdin:
 c.sendall(b'x'*int(line));print('sent',flush=True)
'''
client_code = '''import socket,sys
s=socket.create_connection(('127.0.0.1',int(sys.argv[1])));print('ready',flush=True)
while s.recv(65536):pass
'''
server = subprocess.Popen([sys.executable, '-u', '-c', server_code], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
client = None
try:
    port = server.stdout.readline().strip()
    client = subprocess.Popen([sys.executable, '-u', '-c', client_code, port], stdout=subprocess.PIPE, text=True)
    assert client.stdout.readline().strip() == 'ready'
    assert server.stdout.readline().strip() == 'ready'
    def sample():
        result = subprocess.check_output([str(ROOT / '.build/release/tide-probe'), '--transport-pid', str(client.pid), '--seconds', '1', '--interval', '1'], text=True)
        return json.loads(result.splitlines()[0])
    before = sample()
    payload = 2 * 1024 * 1024
    server.stdin.write(str(payload) + '\n')
    server.stdin.flush()
    assert server.stdout.readline().strip() == 'sent'
    time.sleep(1)
    after = sample()
    received = after['received'] - before['received']
    report = {'test': 'real loopback transfer / production parser', 'payloadBytes': payload, 'observedReceivedDelta': received, 'pass': received == payload}
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence/controlled-transfer.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if not report['pass']:
        raise SystemExit(1)
finally:
    for process in [client, server]:
        if process is not None:
            process.terminate()
            process.wait(timeout=3)
