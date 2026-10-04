"""Exercise the running /detect endpoint against the real phone photos."""
import json
import sys
from pathlib import Path

import requests

BASE = 'http://127.0.0.1:8001'
UPLOADS = Path(r'C:\xampp\htdocs\Farmspot\ml_service\uploads')

# What the old YOLOE hybrid reported on these, for comparison.
KNOWN = {
    '5400': 'hybrid: kamatis .948, lettuce .549',
    '5100': 'hybrid: kamatis .927, lettuce .846',
    '3400': 'hybrid: green_bean .303 (weak)',
    '1900': 'hybrid: lettuce .889, cucumber .838',
    '4800': 'hybrid: nothing',
    '0600': 'hybrid: kamatis .553',
    '8900': 'hybrid: kamatis + cabbage .726',
    '7100': 'hybrid: green_bean .347 (weak)',
    '3500': 'hybrid: lettuce .889',
    '2600': 'hybrid: kamatis + lettuce',
}


def find(suffix):
    hits = sorted(UPLOADS.glob(f'*{suffix}.jpg'))
    return hits[0] if hits else None


def post(path, photo, conf=None):
    with photo.open('rb') as fh:
        files = {'file': (photo.name, fh, 'image/jpeg')}
        params = {'conf': conf} if conf is not None else None
        r = requests.post(f'{BASE}{path}', files=files, params=params, timeout=120)
        r.raise_for_status()
        return r.json()


health = requests.get(f'{BASE}/health', timeout=30).json()
print('health:', json.dumps(health))
print()

print('%-6s %-46s %s' % ('photo', 'prior (YOLOE hybrid)', 'new 9-class'))
print('-' * 96)
for suffix, prior in KNOWN.items():
    photo = find(suffix)
    if photo is None:
        print(f'{suffix:<6} {prior:<46} (file not found)')
        continue
    try:
        dets = post('/detect', photo)['detections']
    except Exception as exc:
        print(f'{suffix:<6} {prior:<46} ERROR {exc}')
        continue
    got = ', '.join(f"{d['name']} {d['confidence']}" for d in dets) or '(none)'
    print(f'{suffix:<6} {prior:<46} {got}')

print()
print('=' * 96)
print('LOW-THRESHOLD PROBE (?conf=0.10) - shows what the model sees before filtering')
for suffix in ('3400', '7100', '4800'):
    photo = find(suffix)
    if photo is None:
        continue
    dets = post('/detect', photo, conf=0.10)['detections']
    got = ', '.join(f"{d['name']} {d['confidence']}" for d in dets) or '(none)'
    print(f'  {suffix}: {got}')