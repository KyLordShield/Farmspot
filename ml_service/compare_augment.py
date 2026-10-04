"""A/B the FastAPI detector with TTA off vs on, on the real phone uploads.

Usage (server must already be running on :8001):

    .venv\\Scripts\\python.exe compare_augment.py            # latest 12 photos
    .venv\\Scripts\\python.exe compare_augment.py path\\to.jpg ...

Reports, per photo, what each mode detected plus which crops only one mode
found. Used to decide whether `augment=True` is worth the extra latency.
"""

import hashlib
import statistics
import sys
import time
from pathlib import Path

import requests

API = "http://127.0.0.1:8001"
UPLOADS = Path(__file__).parent / "uploads"


def detect(path: Path, augment: bool) -> tuple[dict, float]:
    with path.open("rb") as fh:
        started = time.perf_counter()
        resp = requests.post(
            f"{API}/detect",
            files={"file": (path.name, fh, "image/jpeg")},
            params={"augment": str(augment).lower()},
            timeout=300,
        )
        elapsed = time.perf_counter() - started
    resp.raise_for_status()
    return resp.json(), elapsed


def pick_photos(explicit: list[str], limit: int) -> list[Path]:
    if explicit:
        return [Path(p) for p in explicit]

    # Uploads accumulate duplicates (re-sends of the same photo), so dedupe on
    # content hash to make each row a genuinely different picture.
    seen: set[str] = set()
    picked: list[Path] = []
    for p in sorted(UPLOADS.glob("*.jpg"), key=lambda f: f.stat().st_mtime, reverse=True):
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        picked.append(p)
        if len(picked) >= limit:
            break
    return picked


def summarise(payload: dict) -> str:
    dets = payload.get("detections", [])
    if not dets:
        return "(none)"
    return ", ".join(f"{d['name']} {d['confidence']:.2f}" for d in dets)


def main() -> None:
    photos = pick_photos(sys.argv[1:], 12)
    if not photos:
        print("No photos found.")
        return

    print(f"Comparing augment=False vs augment=True on {len(photos)} photo(s)\n")
    header = f"{'photo':<26} {'augment=False':<46} {'augment=True':<46}"
    print(header)
    print("-" * len(header))

    only_true: dict[str, int] = {}
    only_false: dict[str, int] = {}
    agree = 0
    times_off: list[float] = []
    times_on: list[float] = []

    for p in photos:
        off, t_off = detect(p, augment=False)
        on, t_on = detect(p, augment=True)
        times_off.append(t_off)
        times_on.append(t_on)

        off_names = {d["name"] for d in off.get("detections", [])}
        on_names = {d["name"] for d in on.get("detections", [])}

        for name in on_names - off_names:
            only_true[name] = only_true.get(name, 0) + 1
        for name in off_names - on_names:
            only_false[name] = only_false.get(name, 0) + 1
        if off_names == on_names:
            agree += 1

        print(f"{p.name[-24:]:<26} {summarise(off):<46} {summarise(on):<46}")

    print(f"\nIdentical crop sets: {agree}/{len(photos)}")
    print(f"Only found with augment=True : {only_true or '(none)'}")
    print(f"Only found with augment=False: {only_false or '(none)'}")

    def ms(values: list[float]) -> str:
        return (
            f"median {statistics.median(values) * 1000:.0f} ms, "
            f"max {max(values) * 1000:.0f} ms"
        )

    print(f"\nLatency augment=False: {ms(times_off)}")
    print(f"Latency augment=True : {ms(times_on)}")
    if statistics.median(times_off) > 0:
        ratio = statistics.median(times_on) / statistics.median(times_off)
        print(f"Cost of TTA: {ratio:.2f}x")


if __name__ == "__main__":
    main()