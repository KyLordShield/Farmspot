"""Generate the v3 Kaggle notebook from the fixed v2 notebook.

v3 keeps the same validation/test split as v2 for a fair comparison, but uses
every Bangladesh training frame (train_stride=1) and trains for 100 epochs.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V2_NB = ROOT / "zip files datasets" / "train_merged_9class_v2_kaggle.ipynb"
OUT = ROOT / "zip files datasets" / "train_merged_9class_v3_kaggle.ipynb"
SUMMARY = ROOT / "ml_service" / "dataset" / "merged_9class_v3" / "build_summary.json"


def main() -> None:
    notebook = json.loads(V2_NB.read_text(encoding="utf-8"))
    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))

    replacements = [
        ("merged_9class_v2", "merged_9class_v3"),
        ("farmspot_9class_v2_best.pt", "farmspot_9class_v3_best.pt"),
        ("farmspot_9class_v2_results.zip", "farmspot_9class_v3_results.zip"),
        ("'epochs': 30", "'epochs': 100"),
        ("'patience': 10", "'patience': 20"),
        ("30 epochs", "100 epochs"),
        ("3-5 hours", "5-7 hours"),
    ]
    for cell in notebook["cells"]:
        source = "".join(cell.get("source", []))
        for old, new in replacements:
            source = source.replace(old, new)
        cell["source"] = source.splitlines(True)

    boxes = summary["boxes"]["train"]
    header = f"""# FarmSpot mixed-crop fine-tune (merged_9class_v3)

This fine-tunes the existing 9-class detector on the curated Bangladesh
mixed-vegetable set plus the current FarmSpot training data. v3 uses every
Bangladesh training frame (train_stride=1) and keeps the same val/test videos
as v2, so the two runs are directly comparable.

| class | train boxes |
|---|---|
| kamatis | {boxes['kamatis']} boxes |
| lettuce | {boxes['lettuce']} |
| cabbage | {boxes['cabbage']} |
| cucumber | {boxes['cucumber']} |
| chili | {boxes['chili']} |
| green_bean | {boxes['green_bean']} |
| chayote | {boxes['chayote']} |
| bok_choy | {boxes['bok_choy']} |
| not_crop | {boxes['not_crop']} |

Training images: {summary['images']['train']:,}. Validation: {summary['images']['val']:,}. Test: {summary['images']['test']:,}.
Mixed-crop training images: {summary['mixed_images']['train']:,}. Target+unknown: {summary['target_unknown_images']['train']:,}.

The Bangladesh validation/test videos are held out by video, so the metrics are
not inflated by near-identical frames leaking across splits.

**Kaggle GPU is free.** Use a phone-verified account, enable a GPU accelerator,
and run this notebook. This run is sized for a 16 GB T4/P100. If you get CUDA
out-of-memory, change `batch` to 8. Start from `farmspot_9class_best.pt`, not
the 30-epoch v2 checkpoint.
"""
    notebook["cells"][0]["source"] = header.splitlines(True)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(notebook, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
