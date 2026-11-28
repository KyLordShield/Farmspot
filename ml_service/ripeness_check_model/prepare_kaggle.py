"""Build the compact Farmspot classification dataset and Kaggle notebook."""

import argparse
import ast
import csv
from collections import Counter, defaultdict
from dataclasses import dataclass, replace
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import random
import re
from textwrap import dedent
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

from PIL import Image, ImageOps


OUTPUT = Path(__file__).resolve().parent
WEIGHTS = 'ripeness_yolo26s-cls_best.pt'
ARCHIVE = 'farmspot_quality_4crop_kaggle.zip'
SPLITS = {'train': 'train', 'valid': 'val', 'val': 'val', 'test': 'test'}
QUOTAS = {'train': 0.70, 'val': 0.15, 'test': 0.15}
IMAGE_SUFFIXES = {'.jpg', '.jpeg', '.png', '.webp'}

DETECTION_SOURCES = {
    'cabbage': (
        'Cabbage detection*.zip',
        {'fresh cabbage': 'cabbage_fresh', 'rotten cabbage': 'cabbage_rotten'},
    ),
    'chili': (
        'Chili Maturity and Condition*.zip',
        {'Ripe': 'chili_ripe', 'Unripe': 'chili_unripe', 'Rot': 'chili_rotten'},
    ),
    'lettuce': (
        'Lettuce Freshness*.zip',
        {'fresh': 'lettuce_fresh', 'not-fresh': 'lettuce_visibly_degraded'},
    ),
}
TOMATO_LABELS = {
    'raw': 'tomato_unripe',
    'half_ripe': 'tomato_half_ripe',
    'ripe': 'tomato_ripe',
    'rotten': 'tomato_rotten',
}
CLASS_CAPS = {
    'tomato_unripe': 410,
    'tomato_half_ripe': 510,
    'tomato_ripe': 550,
    'tomato_rotten': 220,
    'cabbage_fresh': 360,
    'cabbage_rotten': 310,
    'chili_ripe': 560,
    'chili_unripe': 430,
    'chili_rotten': 155,
    'lettuce_fresh': 100,
    'lettuce_visibly_degraded': 100,
}

TOMATO_VARIANT = re.compile(r'(?:_(?:original|rotated_\d+|flipped_[hv]))*_(?:jpe?g|png|webp)$')


@dataclass(frozen=True)
class Candidate:
    source: str
    split: str
    label: str
    group: str
    image: str
    box: tuple[float, ...] | None = None


def source_group(filename):
    return PurePosixPath(filename).stem.split('.rf.')[0].casefold()


def detection_candidates(source_dir, archive, mapping):
    yaml_path = source_dir / 'data.yaml'
    config = yaml_path.read_bytes()
    assert config.decode().splitlines() == archive.read('data.yaml').decode().splitlines(), (
        f'{yaml_path} differs from the original export.'
    )
    classes = ast.literal_eval(re.search(rb'^names:\s*(\[.*\])', config, re.M)[1].decode())
    images = {
        (p.parts[0], p.stem): str(p)
        for name in archive.namelist()
        if len((p := PurePosixPath(name)).parts) == 3
        and p.parts[1] == 'images'
        and p.suffix.lower() in IMAGE_SUFFIXES
    }
    extracted_labels = {
        (split, label.stem)
        for split in SPLITS
        for label in (source_dir / split / 'labels').glob('*.txt')
    }
    candidates = []
    for member in archive.namelist():
        parts = PurePosixPath(member).parts
        if len(parts) != 3 or parts[1] != 'labels' or parts[0] not in SPLITS:
            continue
        stem = PurePosixPath(member).stem
        image = images.get((parts[0], stem))
        if image is None:
            continue
        if (parts[0], stem) not in extracted_labels:
            continue
        for row in archive.read(member).splitlines():
            values = row.split()
            if len(values) != 5:
                continue
            label = mapping.get(classes[int(values[0])])
            if label:
                candidates.append(Candidate(
                    source_dir.name, SPLITS[parts[0]], label,
                    source_group(image), image, tuple(map(float, values[1:])),
                ))
    return candidates


def tomato_candidates(source_dir, archive):
    for member in archive.namelist():
        path = PurePosixPath(member)
        if len(path.parts) != 4 or path.parts[0] != 'cls_tomato':
            continue
        _, split, label, _ = path.parts
        if (
            split in SPLITS and label in TOMATO_LABELS
            and path.suffix.lower() in IMAGE_SUFFIXES
            and not re.search(r'_a\d+$', path.stem)
        ):
            yield Candidate(
                source_dir.name, SPLITS[split], TOMATO_LABELS[label],
                TOMATO_VARIANT.sub('', source_group(member)), member,
            )


def render_crop(archive, candidate):
    with Image.open(BytesIO(archive.read(candidate.image))) as original:
        image = original.convert('RGB')
    if candidate.box is not None:
        x, y, width, height = candidate.box
        w, h = image.size
        bounds = (
            max(0, int((x - 0.6 * width) * w)),
            max(0, int((y - 0.6 * height) * h)),
            min(w, int((x + 0.6 * width + 1 / w) * w)),
            min(h, int((y + 0.6 * height + 1 / h) * h)),
        )
        if bounds[2] - bounds[0] < 12 or bounds[3] - bounds[1] < 12:
            return None
        image = image.crop(bounds)
    padding = (114, 114, 114)
    # Keep the original crop identity so the 160 and 224 exports use the same selection.
    identity = ImageOps.pad(image, (160, 160), Image.Resampling.LANCZOS, color=padding)
    digest = sha256(identity.tobytes()).hexdigest()
    image = ImageOps.pad(image, (224, 224), Image.Resampling.LANCZOS, color=padding)
    buffer = BytesIO()
    image.save(buffer, format='JPEG', quality=93)
    return digest, buffer.getvalue()


def notebook():
    def cell(kind, source):
        source = dedent(source).strip()
        result = {'cell_type': kind, 'metadata': {}, 'source': source.splitlines(keepends=True)}
        if kind == 'code':
            compile(source, '<Kaggle cell>', 'exec')
            result.update(execution_count=None, outputs=[])
        return result

    return {
        'nbformat': 4,
        'nbformat_minor': 4,
        'metadata': {'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'}},
        'cells': [
            cell('markdown', """
                # Farmspot crop condition classifier

                Attach farmspot_quality_4crop_kaggle.zip and farmspot_kaggle_offline_dependencies.zip as Kaggle datasets. Enable a GPU accelerator and run all cells. The installation uses local package files.

                The archive includes the pretrained tomato classifier and cropped images for tomato, cabbage, chili, and lettuce. Lettuce has a small exploratory holdout. The labels describe visible condition. See README.txt for source credits.
            """),
            cell('code', """
                import os
                import subprocess
                import sys
                from pathlib import Path
                from zipfile import ZipFile

                os.environ['YOLO_AUTOINSTALL'] = 'false'
                inputs = Path('/kaggle/input')
                archives = list(inputs.rglob('farmspot_kaggle_offline_dependencies.zip'))
                if archives:
                    wheel_dir = Path('/kaggle/working/farmspot_offline_wheels')
                    wheel_dir.mkdir(parents=True, exist_ok=True)
                    with ZipFile(archives[0]) as archive:
                        archive.extractall(wheel_dir)
                else:
                    wheel = next(inputs.rglob('ultralytics-8.4.106-*.whl'), None)
                    wheel_dir = wheel.parent if wheel else None

                if wheel_dir is None:
                    raise FileNotFoundError('Attach the Farmspot Offline Dependencies dataset using Add Input.')

                subprocess.check_call([
                    sys.executable, '-m', 'pip', 'install', '--no-index', '--disable-pip-version-check',
                    '--find-links', str(wheel_dir), 'ultralytics==8.4.106',
                ])
                import ultralytics
                print('Offline setup complete. Ultralytics', ultralytics.__version__)
            """),
            cell('code', """
                import json
                from pathlib import Path
                from zipfile import ZipFile

                import torch
                from ultralytics import YOLO

                inputs = Path('/kaggle/input')
                working = Path('/kaggle/working')
                archives = list(inputs.rglob('farmspot_quality_4crop_kaggle.zip'))
                if archives:
                    bundle = working / 'farmspot_quality_4crop_input'
                    bundle.mkdir(exist_ok=True)
                    with ZipFile(archives[0]) as archive:
                        archive.extractall(bundle)
                else:
                    manifests = list(inputs.rglob('farmspot_quality_4crop_manifest.json'))
                    if len(manifests) != 1:
                        raise FileNotFoundError('Attach the Farmspot quality dataset as a Kaggle input.')
                    bundle = manifests[0].parent

                dataset = bundle / 'dataset'
                weights = bundle / 'ripeness_yolo26s-cls_best.pt'
                manifest = json.loads((bundle / 'farmspot_quality_4crop_manifest.json').read_text())
                expected = set(manifest['classes'])
                for split in ('train', 'val', 'test'):
                    folders = {p.name for p in (dataset / split).iterdir() if p.is_dir()}
                    assert folders == expected, (split, folders, expected)
                    print(split, {name: len(list((dataset / split / name).glob('*.jpg'))) for name in sorted(folders)})
                assert weights.is_file(), 'The pretrained tomato checkpoint is missing.'
                assert torch.cuda.is_available(), 'Enable a GPU accelerator in Kaggle settings.'
                print(torch.cuda.get_device_name(0))
            """),
            cell('code', """
                EPOCHS = 60
                BATCH_SIZE = 32
                IMAGE_SIZE = 224
                SEED = 42

                classifier = YOLO(str(weights), task='classify')
                classifier.train(
                    data=str(dataset), epochs=EPOCHS, imgsz=IMAGE_SIZE, batch=BATCH_SIZE,
                    device=0, workers=2, seed=SEED, patience=15,
                    project=str(working / 'farmspot_runs'), name='quality_classifier_4crop',
                    auto_augment=None, erasing=0.0, hsv_h=0.0, hsv_s=0.0,
                    hsv_v=0.0, fliplr=0.5, amp=False,
                )
                best_path = Path(classifier.trainer.best)
                assert best_path.is_file(), best_path
            """),
            cell('code', """
                import shutil

                from sklearn.metrics import classification_report, confusion_matrix

                best = YOLO(str(best_path), task='classify')
                test_images = sorted((dataset / 'test').glob('*/*.jpg'))
                names = sorted(expected)
                actual = [photo.parent.name for photo in test_images]
                predicted = []
                for start in range(0, len(test_images), BATCH_SIZE):
                    batch = test_images[start:start + BATCH_SIZE]
                    predictions = best.predict(
                        [str(photo) for photo in batch], imgsz=IMAGE_SIZE,
                        device=0, verbose=False,
                    )
                    predicted.extend(result.names[result.probs.top1] for result in predictions)
                print(classification_report(actual, predicted, labels=names, zero_division=0))
                report = classification_report(
                    actual, predicted, labels=names, zero_division=0, output_dict=True,
                )
                (working / 'farmspot_quality_4crop_test_report.json').write_text(json.dumps(report, indent=2))
                matrix = confusion_matrix(actual, predicted, labels=names).tolist()
                (working / 'farmspot_quality_4crop_confusion.json').write_text(
                    json.dumps({'labels': names, 'rows_actual_columns_predicted': matrix}, indent=2)
                )
                shutil.copy2(best_path, working / 'farmspot_quality_4crop_best.pt')
            """),
        ],
    }


def build(source_root):
    from contextlib import ExitStack

    with ExitStack() as stack:
        archives = {
            source: stack.enter_context(ZipFile(next(source_root.glob(pattern))))
            for source, (pattern, _) in DETECTION_SOURCES.items()
        }
        archives['tomato'] = stack.enter_context(ZipFile(source_root / 'tomato_ripeness_crops.zip'))
        build_archive(source_root, archives)


def build_archive(source_root, archives):
    rng = random.Random(42)
    pools = defaultdict(list)
    group_split = {}
    split_rank = dict(train=0, val=1, test=2)
    with (OUTPUT / 'lettuce_review.csv').open(newline='') as review_file:
        lettuce_review = {row['source_group']: row for row in csv.DictReader(review_file)}
    for source, (_, mapping) in DETECTION_SOURCES.items():
        items = detection_candidates(source_root / source, archives[source], mapping)
        if source == 'lettuce':
            by_original = {}
            for item in items:
                review = lettuce_review.get(item.group)
                if review is None or item.label != review['label']:
                    continue
                previous = by_original.get(item.group)
                area = item.box[2] * item.box[3]
                if previous is None or area > previous.box[2] * previous.box[3]:
                    by_original[item.group] = item
            assert by_original.keys() == lettuce_review.keys(), 'Lettuce export differs from the reviewed set.'
            items = [
                replace(item, split=lettuce_review[group]['split'], group=lettuce_review[group]['capture_group'])
                for group, item in by_original.items()
            ]
        for item in items:
            pools[item.label].append(item)
    for item in tomato_candidates(source_root / 'tomato', archives['tomato']):
        pools[item.label].append(item)
    for items in pools.values():
        for item in items:
            key = (item.source, item.group)
            chosen = group_split.get(key, item.split)
            # Tomato validation/test must stay separate from the base checkpoint's
            # original training images. For a new crop, reserve overlapping
            # variants for evaluation to retain rare classes in the holdout.
            prefer = min if item.source == 'tomato' else max
            group_split[key] = prefer(chosen, item.split, key=split_rank.__getitem__)

    counts = defaultdict(Counter)
    records = []
    written_pixels = set()
    weights_path = OUTPUT / WEIGHTS
    print('Writing classifier crops', flush=True)
    pending_archive = OUTPUT / (ARCHIVE + '.tmp')
    with ZipFile(pending_archive, mode='w', compression=ZIP_DEFLATED) as result:
        result.write(weights_path, WEIGHTS, compress_type=ZIP_STORED)
        for split, fraction in QUOTAS.items():
            for label, cap in CLASS_CAPS.items():
                items = sorted(pools[label], key=lambda item: (item.image, item.box or ()))
                by_group = defaultdict(list)
                for item in items:
                    by_group[item.source, item.group].append(item)
                groups = list(by_group)
                rng.shuffle(groups)
                items = [
                    item for group in groups
                    for item in sorted(
                        by_group[group],
                        key=lambda candidate: (
                            -candidate.box[2] * candidate.box[3] if candidate.box else
                            bool(re.search(r'_(?:rotated|flipped)_', candidate.image))
                        ),
                    )
                ]
                seen_groups = set()
                for item in items:
                    key = (item.source, item.group)
                    if item.split != split or group_split[key] != split or key in seen_groups:
                        continue
                    crop = render_crop(archives[item.source], item)
                    if crop is None:
                        continue
                    digest, pixels = crop
                    if digest in written_pixels:
                        continue
                    written_pixels.add(digest)
                    if item.source != 'lettuce':
                        seen_groups.add(key)
                    counts[split][label] += 1
                    name = f'dataset/{split}/{label}/{digest[:20]}.jpg'
                    result.writestr(name, pixels, compress_type=ZIP_STORED)
                    records.append({
                        'file': name, 'source': item.source, 'source_image': item.image,
                        'source_group': item.group,
                    })
                    if counts[split][label] >= round(cap * fraction):
                        break
                if counts[split][label] == 0:
                    raise ValueError(f'No {split} images for {label}.')
            print(split, dict(counts[split]), flush=True)
        dataset_manifest = {
            'classes': sorted(CLASS_CAPS),
            'seed': 42,
            'image_size': 224,
            'counts': counts,
            'starting_checkpoint_sha256': sha256(weights_path.read_bytes()).hexdigest(),
            'training_images': records,
        }
        result.writestr('farmspot_quality_4crop_manifest.json', json.dumps(dataset_manifest, indent=2))
        result.writestr('README.txt', dedent("""
            Farmspot crop condition classification
            ======================================

            Attach this ZIP as a Kaggle Dataset and import train_farmspot_quality_4crop.ipynb.
            Enable a GPU and attach the offline dependencies. Internet can stay off. The training notebook produces
            farmspot_quality_4crop_best.pt and farmspot_quality_4crop_test_report.json.

            The classifier trains on 224 x 224 crops of tomato, cabbage, chili and lettuce.
            Lettuce visibly degraded includes clear visual deterioration. It
            is an exploratory grade and does not establish saleability, days
            remaining, or harvest date. Source review is in lettuce_review.csv.
            Related lettuce capture sequences stay in training only. The
            lettuce holdout is too small to estimate field performance reliably.

            Original tomato, cabbage and chili split membership was used, with
            a single split per source filename group. Named rotations and flips
            of tomatoes share a group. Tomato training took precedence to keep
            variants of the starting checkpoint's training data out of evaluation.
            Cabbage and chili prioritized test and validation when groups overlapped.
            Identical standardized crops were removed. The split audit records
            filenames and groups. Independent Farmspot phone photos are necessary
            to measure accuracy on actual listings.

            Source and license as published by the dataset owners
            - Tomato images: ParsaVictor Unified Tomato Detection & Ripeness,
              CC BY 4.0, https://huggingface.co/datasets/ParsaVictor/tomato-ripeness-detection
            - Base classifier: ParsaVictor YOLO26s tomato classifier,
              AGPL-3.0, https://huggingface.co/ParsaVictor/tomato-ripeness-classifier-yolo26s
            - Cabbage: Penulisan Ilmiah dataset v2, CC BY 4.0,
              https://universe.roboflow.com/penulisan-ilmiah-dataset/cabbage-detection/dataset/2
            - Chili: University of Southeastern Philippines v2, CC BY 4.0,
              https://universe.roboflow.com/university-of-southeastern-philippines-cnl9c/chili-maturity-and-condition-datasets/dataset/2
            - Lettuce: Muhammad Bagus Adi Prayoga v2, CC BY 4.0,
              https://universe.roboflow.com/muhammad-bagus-adi-prayoga-zjz41/lettuce-freshness/dataset/2
        """).strip() + '\n')
        result.write(OUTPUT / 'lettuce_review.csv', 'lettuce_review.csv')
    pending_archive.replace(OUTPUT / ARCHIVE)
    (OUTPUT / 'train_farmspot_quality_4crop.ipynb').write_text(json.dumps(notebook(), indent=1), encoding='utf-8')
    print({split: sum(values.values()) for split, values in counts.items()}, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_root', type=Path)
    build(parser.parse_args().source_root)
