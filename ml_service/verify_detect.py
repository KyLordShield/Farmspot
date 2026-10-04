"""Regression check for the detector against the labelled phone photos.

Run after ANY change to app.py tuning, model, or thresholds:

    .venv\\Scripts\\python.exe verify_detect.py

Each case lists the crops the photo is KNOWN to contain. `min` is the crops that
must be present; `exact` additionally forbids anything else, which is what stops
a false positive from being introduced unnoticed.

Two prior changes are guarded here specifically, because both looked like
improvements on a small sample and were not:

  - augment=True hallucinated a cucumber on a lettuce-only photo and a bok_choy
    on a chayote/cabbage photo.
  - imgsz=1280 returned NOTHING for four of the six cucumber photos.

Both are therefore asserted OFF/960, and the notes in app.py say why.
"""

import os
import sys

import requests

# The host's port 8001 can be held by orphaned sockets from dead uvicorn
# processes, which answer with a stale app.py. Serving on 8005 and bridging with
# `adb reverse tcp:8001 tcp:8005` avoids that, so the port is configurable.
HOST = os.environ.get('DETECT_HOST', '127.0.0.1')
PORT = os.environ.get('DETECT_PORT', '8001')
BASE = f'http://{HOST}:{PORT}'
ENDPOINT = f'{BASE}/detect'
TIMEOUT = 300

CASES = [
    # (file, description, exact set of crops expected with reclassify off)
    ('1791106506936222600.jpg', 'lettuce + cucumber (cucumber missed)',
     {'lettuce'}),
    ('1791106627975001000.jpg', 'cucumber only', {'cucumber'}),
    ('1791106578583950600.jpg', 'lettuce only', {'lettuce'}),
    ('1791105999754338100.jpg', 'cucumber only', {'cucumber'}),
    ('1791106048714358100.jpg', 'cucumber only', {'cucumber'}),
    ('1791099548662230900.jpg', 'chayote + cabbage + carrot',
     {'chayote', 'cabbage'}),
    ('1791099169307248900.jpg', 'banana, must reject', set()),
    # Known-missed cases. These are recorded as failures on purpose: they are
    # the multi-crop gap that only retraining closes, and a regression here
    # should never be silently "fixed" by loosening a bar.
    ('1791109002521358700.jpg', 'tomato + cucumber in hand (cucumber missed)',
     {'kamatis'}),
]

# With reclassify on, one photo gains the crop pass 1 misses.
RECLASSIFY_EXPECTED = {
    '1791109428635647200.jpg': ({'cucumber', 'kamatis'},
                               'cucumber front + tomato behind'),
}


def detect(filename, reclassify):
    with open(f'uploads/{filename}', 'rb') as fh:
        response = requests.post(
            ENDPOINT,
            files={'file': (filename, fh, 'image/jpeg')},
            params={'reclassify': str(reclassify).lower()},
            timeout=TIMEOUT,
        )
    response.raise_for_status()
    return response.json()


def main():
    try:
        health = requests.get(f'{BASE}/health', timeout=30).json()
    except requests.RequestException as exc:
        sys.exit(f'server not reachable at {BASE} ({exc})')

    failures = []
    if health['inference']['augment'] is not False:
        failures.append(
            f"augment is {health['inference']['augment']}, must be False "
            '(it hallucinates extra crops)')
    if health['inference']['imgsz'] != 960:
        failures.append(
            f"imgsz is {health['inference']['imgsz']}, must be 960 "
            '(1280 loses cucumber entirely)')

    for filename, description, expected in CASES:
        got = {d['name'] for d in detect(filename, False)['detections']}
        ok = got == expected
        if not ok:
            failures.append(f'{filename} ({description}): '
                            f'expected {sorted(expected) or "no crops"}, '
                            f'got {sorted(got) or "no crops"}')
        print(f"{'PASS' if ok else 'FAIL'}  {description:<46} "
              f'{sorted(got) or "(none)"}')

    for filename, (expected, description) in RECLASSIFY_EXPECTED.items():
        got = {d['name'] for d in detect(filename, True)['detections']}
        ok = got == expected
        if not ok:
            failures.append(f'{filename} reclassify ({description}): '
                            f'expected {sorted(expected)}, got {sorted(got)}')
        print(f"{'PASS' if ok else 'FAIL'}  reclassify: {description:<38} "
              f'{sorted(got) or "(none)"}')

    print('-' * 70)
    if failures:
        print(f'{len(failures)} FAILURE(S):')
        for line in failures:
            print(f'  - {line}')
        sys.exit(1)
    print('all detector regressions passed')


if __name__ == '__main__':
    main()