import io
import os
import pathlib
import threading
import time

from fastapi import FastAPI, HTTPException, Query, UploadFile
from PIL import Image
from ultralytics import YOLO

app = FastAPI()

BASE = pathlib.Path(os.environ.get('ML_SERVICE_DIR', pathlib.Path(__file__).resolve().parent))
UPLOADS = BASE / 'uploads'
UPLOADS.mkdir(parents=True, exist_ok=True)

MODEL_PATH = BASE / os.environ.get('MODEL_FILE', 'farmspot_9class_best.pt')

# Per-request detector trace, written by the app itself (see _log_detect).
DETECT_LOG = BASE / 'detect_log.txt'

# ===========================================================================
# TUNING - everything worth changing lives in this block.
# ===========================================================================

# Inference settings. These are separate from the per-crop bars below because
# they control what the model is even allowed to see.
#
# imgsz was 640 (the ultralytics default), which is too small for a crop that
# occupies part of a phone photo rather than the whole frame. 960 recovers
# those, at roughly 2x the inference cost.
#
# 1280 was tried and is WORSE, so do not raise it. A spot check on two photos
# suggested it helped (it removed a spurious `not_crop 0.457` and lifted kamatis
# from 0.67 to 0.89), but across all nine labelled photos it destroys cucumber
# detection: four of the six cucumber photos return NOTHING at 1280, because the
# higher resolution pushes the cucumber into the not_crop class. Two samples was
# not enough to see it. Verified comparison, 960 vs 1280:
#     cucumber 0.519 -> (none)      cucumber 0.872 -> (none)
#     cucumber 0.551 -> (none)      cucumber+tomato 0.453 -> (none)
# conf_floor was 0.40, which silently discarded secondary crops in a mixed
# photo before any per-crop bar could be applied. 0.25 is the ultralytics
# default and is what stops that happening.
# iou 0.5 instead of the 0.7 default: 0.7 is lenient enough to merge two
# genuinely different vegetables sitting next to each other.
#
# augment (test-time augmentation: scales/flips/rotations, results merged) is
# OFF, deliberately.
#
# It was briefly enabled after an A/B over the phone uploads appeared to favour
# it, but that A/B was wrong: the "extra crops" it recovered were hallucinations
# on single-crop photos. Verified against known ground truth, augment=True put
# a spurious `cucumber 0.536` on a lettuce-only photo, while augment=False was
# correct on every known photo. TTA also inflates confidence (a real cucumber
# reads 0.52 without it, 0.82 with), which makes false positives look stronger
# rather than weaker. Set AUGMENT=1 to re-enable and re-run
# compare_augment.py if you get fresh labelled photos.
INFERENCE = {
    'imgsz': int(os.environ.get('IMGSZ', '960')),
    'iou': float(os.environ.get('IOU', '0.5')),
    'conf_floor': float(os.environ.get('CONF_FLOOR', '0.25')),
    'augment': os.environ.get('AUGMENT', '0') == '1',
    'max_det': int(os.environ.get('MAX_DET', '100')),
}

CLASS_MIN_CONF = {
        'kamatis': float(os.environ.get('CONF_KAMATIS', '0.60')),
        'lettuce': float(os.environ.get('CONF_LETTUCE', '0.35')),
        'cabbage': float(os.environ.get('CONF_CABBAGE', '0.35')),
        'cucumber': float(os.environ.get('CONF_CUCUMBER', '0.35')),
        'chili': float(os.environ.get('CONF_CHILI', '0.35')),
        'green_bean': float(os.environ.get('CONF_GREEN_BEAN', '0.35')),
        'chayote': float(os.environ.get('CONF_CHAYOTE', '0.35')),
        'bok_choy': float(os.environ.get('CONF_BOK_CHOY', '0.35')),
        'carrot': float(os.environ.get('CONF_CARROT', '0.35')),
    }

# squash and sword_bean are deliberately absent: the training data has no
# examples of either, so nothing can detect them reliably.

# Class 8 is a trained class, not a filter. Because YOLO assigns one label per
# box, a banana gets a not_crop box *instead of* a tomato box, so simply
# dropping these rejects the photo without needing any veto logic.
REJECT_CLASS = 'not_crop'

# Model-aware canonicalisation
MODEL_63 = 'fruit_vegetable_yolov8m.pt'

# Map canonical crop names (what API returns) to label aliases in the current model.
# Aliases split on '/' and matched case-insensitively (whole token/label).
CANONICAL_ALIASES = {
    'kamatis': ['kamatis', 'tomato'],
    'lettuce': ['lettuce'],
    'cucumber': ['cucumber', 'cuke'],
    'chili': ['chili', 'chilli', 'chilly'],
    'green_bean': ['green bean', 'green_bean'],
    'cabbage': ['cabbage'],
    'chayote': ['chayote'],
    'bok_choy': ['bok_choy', 'bok choy', 'pak choi', 'chinese cabbage'],
    'carrot': ['carrot'],
}

# ===========================================================================
# SECOND-PASS RE-CLASSIFICATION (experimental, OFF by default)
# ===========================================================================
#
# The model frequently LOCALIZES a real crop correctly but labels it not_crop.
# That is a class-prior effect, not a detection failure: not_crop is the largest
# class in the training set (1,977 boxes, 28.6% of all annotations, more than
# kamatis at 1,167 or cucumber at 1,025), so it is the statistically safest
# answer for a region the classifier is unsure about. The same pull explains a
# green cucumber being read as lettuce.
#
# This pass takes each not_crop box that plausibly bounds a single object, crops
# it from the ORIGINAL image at native resolution, and re-runs the classifier on
# just that crop. A small crop kept at full resolution is far more legible to the
# classifier than the same region downscaled into a 960px frame.
#
# Evidence across the nine labelled photos at bar=0.70:
#   - recovers `kamatis 0.739` on the cucumber-front/tomato-behind photo that
#     pass 1 reports as cucumber only. This is the case it was written for.
#   - no false positives, no change to the other seven, banana still rejected.
#   - at bar=0.50 it produces a false positive (a cucumber-only photo also gains
#     kamatis 0.634); at 0.75 it loses the fix. So the usable window is narrow.
#
# OFF by default because the margins are thin: the recovered box sits at 0.739
# against a 0.70 bar, and nine photos is not enough separation to trust
# unattended. Enable with RECLASSIFY=1, or per request with
# /detect?reclassify=true, and A/B it against real photos before leaving it on.
#
# It cannot recover a crop that was never localized as its own box at all (the
# in-hand cucumber, the cucumber beside lettuce). Those need retraining.
#
# Cost: one extra inference per candidate box, so photos containing not_crop
# boxes run roughly 1.8x slower.
RECLASSIFY = {
    'enabled': os.environ.get('RECLASSIFY', '0') == '1',
    # Boxes weaker than this are not even considered as candidates.
    'floor': float(os.environ.get('RECLASSIFY_FLOOR', '0.02')),
    # A candidate must be neither tiny nor scene-sized. Scene-sized boxes are
    # usually background, and re-classifying a near-full-frame crop just returns
    # whatever dominant object it happens to contain.
    'area_min': float(os.environ.get('RECLASSIFY_AREA_MIN', '0.005')),
    'area_max': float(os.environ.get('RECLASSIFY_AREA_MAX', '0.20')),
    'min_side': int(os.environ.get('RECLASSIFY_MIN_SIDE', '60')),
    'pad': float(os.environ.get('RECLASSIFY_PAD', '0.12')),
    'bar': float(os.environ.get('RECLASSIFY_BAR', '0.70')),
}

_lock = threading.Lock()
_model = None


def _canonical_name_for_label(label: str) -> str | None:
    s = str(label).strip().lower()
    for canonical, aliases in CANONICAL_ALIASES.items():
        for a in aliases:
            a_clean = a.strip().lower()
            if a_clean == s:
                return canonical
            # also match if label equals any slash token? names already slash-joined but just in case
            if '/' in s:
                for tok in s.split('/'):
                    if tok.strip() == a_clean:
                        return canonical
    # special case: new model uses 'gourd' etc â€” not mapped to our 9; ignore
    return None


def _is_reject_label(label: str) -> bool:
    s = str(label).strip().lower()
    if REJECT_CLASS and s == REJECT_CLASS.lower():
        return True
    # new model has no not_crop; be explicit
    if MODEL_PATH.name == MODEL_63:
        return False
    return False


def crop_indices(model):
    idx = {}
    names = model.names
    # ultralytics returns dict {i: name} or list
    try:
        if hasattr(names, 'items'):
            items = list(names.items())
        else:
            items = list(enumerate(names))
    except Exception:
        items = []
    for i, n in items:
        try:
            c = _canonical_name_for_label(n)
            if not c:
                continue
            idx.setdefault(c, []).append(int(i))
        except Exception:
            continue
    return idx


def load_model():
    global _model
    if _model is not None:
        return _model
    with _lock:
        if _model is None:
            if not MODEL_PATH.exists():
                raise HTTPException(
                    status_code=503,
                    detail=f'model not found: {MODEL_PATH}',
                )
            _model = YOLO(str(MODEL_PATH))
    return _model


def _reclassify_rejects(model, image, settings, bars, cfg):
    """Second pass over not_crop boxes; return {name: (score, box)} to promote.

    Runs its own pass at a low floor, because the rejected regions of interest
    sit below the normal conf_floor and would otherwise never be seen.

    A candidate is only reconsidered if it plausibly bounds one object, and the
    re-classified crop must beat both RECLASSIFY_BAR and that crop's own per-crop
    bar before it is promoted. Classes already detected in pass 1 are filtered
    out by the caller, so this can only add a crop, never restate one.
    """
    promoted = {}
    if not cfg['enabled']:
        return promoted

    width, height = image.size
    area = width * height

    candidates = model.predict(
        image,
        conf=cfg['floor'],
        iou=settings['iou'],
        imgsz=settings['imgsz'],
        augment=settings['augment'],
        max_det=settings['max_det'],
        verbose=False,
    )[0]

    for box in candidates.boxes:
            if MODEL_PATH.name != MODEL_63 and candidates.names[int(box.cls)] != REJECT_CLASS:
                continue
        
                x1, y1, x2, y2 = (int(v) for v in box.xyxy[0])
                box_w, box_h = x2 - x1, y2 - y1
                if box_w < cfg['min_side'] or box_h < cfg['min_side']:
                    continue
                if not cfg['area_min'] <= (box_w * box_h) / area <= cfg['area_max']:
                    continue
                
                pad = int(cfg['pad'] * max(box_w, box_h))
                origin_x = max(0, x1 - pad)
                origin_y = max(0, y1 - pad)
                crop = image.crop((
                    origin_x, origin_y,
                    min(width, x2 + pad), min(height, y2 + pad),
                ))
                
                sub = model.predict(
                    crop,
                    conf=settings['conf_floor'],
                    iou=settings['iou'],
                    imgsz=settings['imgsz'],
                    augment=settings['augment'],
                    max_det=settings['max_det'],
                    verbose=False,
                )[0]
                
                for sbox in sub.boxes:
                    label = sub.names[int(sbox.cls)]
                    name = label
                    cname = _canonical_name_for_label(label)
                    if cname is None:
                        continue
                    name = cname
                    score = float(sbox.conf)
                    # reject class only for old model
                    if MODEL_PATH.name != MODEL_63 and label == REJECT_CLASS:
                        continue
                    if score < cfg['bar'] or score < bars.get(name, settings['conf_floor']):
                        continue
                    if score > promoted.get(name, (0.0,))[0]:
                        # sub reports coordinates within the crop, so shift them back
                        sx1, sy1, sx2, sy2 = (int(v) for v in sbox.xyxy[0])
                        promoted[name] = (score, [
                            sx1 + origin_x, sy1 + origin_y,
                            sx2 + origin_x, sy2 + origin_y,
                        ])
        
    return promoted


@app.get('/health')
def health():
    # Show what's supported vs gaps for current model
    supported = set(crop_indices(load_model()).keys())
    all_crops = set(CLASS_MIN_CONF.keys())
    missing = sorted(all_crops - supported)
    return {
        'status': 'ok',
        'crops': sorted(CLASS_MIN_CONF),
        'supported': sorted(supported),
        'missing_crops': missing,
        'model': MODEL_PATH.name,
        'inference': INFERENCE,
        'min_conf': CLASS_MIN_CONF,
        'reclassify': RECLASSIFY,
        'unsupported': ['squash', 'sword_bean'],
    }


@app.post('/detect')
async def detect(
    file: UploadFile,
    conf: float | None = Query(default=None, ge=0.0, le=1.0),
    augment: bool | None = Query(default=None),
    imgsz: int | None = Query(default=None, ge=320, le=2560),
    reclassify: bool | None = Query(default=None),
):
    photo = await file.read()
    (UPLOADS / f'{time.time_ns()}.jpg').write_bytes(photo)
    image = Image.open(io.BytesIO(photo)).convert('RGB')

    model = load_model()

    # Query params exist so a photo can be A/B tested from the phone without
    # editing code, e.g. /detect?augment=true or /detect?conf=0.15.
    settings = dict(INFERENCE)
    if augment is not None:
        settings['augment'] = augment
    if imgsz is not None:
        settings['imgsz'] = imgsz

    reclassify_cfg = dict(RECLASSIFY)
    if reclassify is not None:
        reclassify_cfg['enabled'] = reclassify

    # An explicit conf flattens every per-crop bar to one value.
    bars = ({k: conf for k in CLASS_MIN_CONF} if conf is not None
            else CLASS_MIN_CONF)

    # The floor is deliberately the LOWEST bar, not min(bars.values()) across a
    # narrow range, so nothing is thrown away before its own bar is applied.
    result = model.predict(
        image,
        conf=settings['conf_floor'],
        iou=settings['iou'],
        imgsz=settings['imgsz'],
        augment=settings['augment'],
        max_det=settings['max_det'],
        verbose=False,
    )[0]

    # Keep the single best box per crop name, but never drop a class outright:
    best = {}
    rejected = 0
    for box in result.boxes:
        label = result.names[int(box.cls)]
        is_rej = False
        if MODEL_PATH.name != MODEL_63:
            if label == REJECT_CLASS:
                is_rej = True
        # for 63-class no explicit reject
        if is_rej:
            rejected += 1
            continue
        cname = _canonical_name_for_label(label)
        if cname is None:
            # unmapped class from new model (e.g. apple, gourd) â€” ignore for our crop set
            continue
        score = float(box.conf)
        if score < bars.get(cname, settings['conf_floor']):
            continue
        if score > best.get(cname, (0.0,))[0]:
            best[cname] = (score, [int(x) for x in box.xyxy[0]])

    detections = [
        {'name': name, 'confidence': round(score, 3), 'box': box}
        for name, (score, box) in best.items()
    ]

    # Second pass over rejected regions (experimental, off unless enabled).
    # Only classes pass 1 did not already find are added, so the best score for
    # a crop always comes from the pass that is most confident about it.
    promoted = _reclassify_rejects(model, image, settings, bars, reclassify_cfg)
    for name, (score, box) in promoted.items():
        cname = name
        if cname not in best:
            best[cname] = (score, box)
            detections.append({
                'name': cname,
                'confidence': round(score, 3),
                'box': box,
                'via': 'reclassify',
            })

    # Highest confidence first, so the app can show the strongest crop up top.
    detections.sort(key=lambda d: d['confidence'], reverse=True)

    # One line per request recording exactly what was returned. When a photo
    # shows fewer sections in the app than this line lists, the loss is in the
    # Flutter client; when this line itself lists one crop, it is a threshold
    # or model issue. That distinction is otherwise invisible from the phone.
    #
    # Written to its own file rather than through logging, because the server
    # is often started from a terminal without output redirection, and a stale
    # console log is worse than none when you are trying to correlate a phone
    # request with what the detector actually returned.
    _log_detect(
        file.filename, len(photo), settings, conf, reclassify_cfg,
        detections, rejected,
    )

    return {
        'detections': detections,
        'rejected': rejected,
        'settings': settings,
        'reclassify': reclassify_cfg['enabled'],
    }


def _log_detect(filename, nbytes, settings, conf, reclassify_cfg,
                detections, rejected):
    line = (
        f"{time.strftime('%H:%M:%S')} in={filename} bytes={nbytes} "
        f"imgsz={settings['imgsz']} iou={settings['iou']} "
        f"floor={settings['conf_floor']} augment={settings['augment']} "
        f"conf_override={conf} reclassify={reclassify_cfg['enabled']} "
        f"-> {len(detections)} crop(s) "
        f"{[(d['name'], d['confidence']) for d in detections]} "
        f"not_crop={rejected}"
    )
    try:
        with DETECT_LOG.open('a', encoding='utf-8') as fh:
            fh.write(line + '\n')
    except OSError:
        pass
