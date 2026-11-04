#!/usr/bin/env python3
"""Build a small OME-Zarr HCS plate from the two single-image test datasets.

    python scripts/make_test_plate.py            # -> data/PLK1_plate.zarr

Layout (NGFF 0.4):
    PLK1_plate.zarr/B/03/0   <- xy_8bit__nuclei_PLK1_control.ome.zarr
    PLK1_plate.zarr/B/04/0   <- xy_8bit__nuclei_PLK1_inhibition.ome.zarr

The images are copied unchanged (pixels + multiscales metadata); only the
plate/well metadata is created, with ngio.
"""
import shutil
from pathlib import Path

from ngio import ImageInWellPath, create_empty_plate, open_ome_zarr_plate

DATA = Path(__file__).resolve().parent.parent / "data"
PLATE = DATA / "PLK1_plate.zarr"
WELLS = {
    ("B", 3): DATA / "xy_8bit__nuclei_PLK1_control.ome.zarr",
    ("B", 4): DATA / "xy_8bit__nuclei_PLK1_inhibition.ome.zarr",
}

if PLATE.exists():
    shutil.rmtree(PLATE)

create_empty_plate(
    store=str(PLATE),
    name="PLK1_plate",
    images=[ImageInWellPath(row=r, column=c, path="0") for r, c in WELLS],
)

for (row, col), src in WELLS.items():
    dst = PLATE / row / f"{col:02d}" / "0"
    # copy the image group (arrays + .zattrs/.zgroup); skip the bioformats2raw OME/ folder
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("OME"))

plate = open_ome_zarr_plate(str(PLATE))
print(f"{PLATE}: {plate.images_paths()}")
