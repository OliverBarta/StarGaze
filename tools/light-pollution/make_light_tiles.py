#!/usr/bin/env python3
"""
make_light_tiles.py — preprocessing for the "Stargazing Spots" feature (global).

Cuts the World Atlas of Artificial Night Sky Brightness (Falchi et al. 2016,
GFZ Data Services, doi:10.5880/GFZ.1.4.2016.001, CC BY-NC 4.0) into small
5° x 5° tiles that the iOS app bundles (Southern Ontario) or downloads on demand
(everywhere else).

For each tile:
  1. read the matching part of the global GeoTIFF (windowed, never the whole file),
  2. average the radiance (mcd/m^2) onto a 400 x 400 grid (0.0125° ≈ 1.4 km cells),
  3. add the natural sky background and convert to mag/arcsec^2 (SQM),
  4. mask water with Natural Earth land + lakes (required: otherwise lakes and
     oceans look like perfect dark-sky sites),
  5. store 1 byte per cell, compress, write  <out-dir>/<lat0>_<lon0>.bin

Tiles that contain no land are skipped. At the end <out-dir>/index.json lists
every tile in the folder, so the app knows that a missing tile means "ocean".

-------------------------------------------------------------------------------
TILE FORMAT  (the Swift side must match this exactly)
  file name : "<lat0>_<lon0>.bin", lat0/lon0 = SOUTH-WEST corner, multiples of 5,
              e.g. "40_-85.bin" covers lat 40..45, lon -85..-80
  content   : raw DEFLATE (RFC 1951, no zlib header) of cells*cells bytes
              -> on iOS: (data as NSData).decompressed(using: .zlib)
  layout    : row 0 = NORTH edge, column 0 = WEST edge, index = row*cells + col
  value v   : 0        = water / no data (never a stargazing spot)
              1...255  = SQM (mag/arcsec^2) = sqmBase + (v - 1) * sqmStep
                         = 16.000 ... 22.350, step 0.025
              Bortle class is derived from SQM in the app (same table as below).

index.json:
  {"version":2,"tileDeg":5,"cells":400,"sqmBase":16.0,"sqmStep":0.025,
   "tiles":["40_-85","40_-80",...]}
-------------------------------------------------------------------------------
"""

import argparse
import json
import math
import os
import sys
import time
import zlib

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from rasterio.windows import from_bounds as window_from_bounds

TILE_DEG = 5
CELLS = 400                       # 5° / 400 = 0.0125° per cell
SQM_BASE = 16.0
SQM_STEP = 0.025

# 0.171168 mcd/m^2 == exactly 22.00 mag/arcsec^2 with the conversion below
NATURAL_MCD = 0.171168

# Same table must be used in Swift. Bortle k if sqm >= value.
BORTLE_SQM_MIN = [(1, 21.75), (2, 21.60), (3, 21.30), (4, 20.80),
                  (5, 20.30), (6, 19.25), (7, 18.50), (8, 18.00)]  # else 9

PREVIEW_RGBA = [(0, 0, 0, 0), (8, 16, 60, 255), (20, 40, 110, 255), (30, 80, 170, 255),
                (40, 150, 120, 255), (140, 190, 60, 255), (240, 220, 60, 255),
                (250, 160, 40, 255), (240, 80, 30, 255), (200, 20, 40, 255)]

CHECK_POINTS = {
    "London, ON (downtown)": (42.9849, -81.2453),
    "Toronto (downtown)":    (43.6532, -79.3832),
    "Bruce Peninsula NP":    (45.2300, -81.5300),
    "Beijing (centre)":      (39.9042, 116.4074),
    "Gobi, Mongolia":        (43.5000, 104.0000),
}


# ----------------------------------------------------------------------------- helpers
def tile_name(lat0, lon0):
    return f"{lat0}_{lon0}"


def sqm_from_mcd(mcd):
    return -2.5 * np.log10((mcd + NATURAL_MCD) / 1.08e8)


def encode_sqm(sqm):
    v = np.round((sqm - SQM_BASE) / SQM_STEP) + 1
    return np.clip(v, 1, 255).astype(np.uint8)


def decode_bortle(v):
    """byte array -> Bortle array (0 = water)."""
    sqm = SQM_BASE + (v.astype(np.float64) - 1) * SQM_STEP
    b = np.full(v.shape, 9, dtype=np.uint8)
    for k, lim in reversed(BORTLE_SQM_MIN):
        b[sqm >= lim] = k
    b[v == 0] = 0
    return b


def deflate_raw(raw: bytes) -> bytes:
    c = zlib.compressobj(9, zlib.DEFLATED, -15)   # -15 = raw DEFLATE, what iOS .zlib expects
    return c.compress(raw) + c.flush()


def inflate_raw(blob: bytes) -> bytes:
    return zlib.decompress(blob, -15)


class LandShapes:
    """Natural Earth polygons, pre-loaded once with their bounding boxes."""

    def __init__(self, path):
        import shapefile  # pyshp
        self.items = []
        with shapefile.Reader(path) as r:
            for shp in r.iterShapes():
                if shp.points:
                    self.items.append((shp.bbox, shp.__geo_interface__))
        print(f"Loaded {len(self.items)} polygons from {os.path.basename(path)}")

    def in_bbox(self, w, s, e, n):
        return [g for (x0, y0, x1, y1), g in self.items
                if not (x1 < w or x0 > e or y1 < s or y0 > n)]


def land_mask(land, lakes, w, s, e, n):
    transform = from_bounds(w, s, e, n, CELLS, CELLS)
    geoms = land.in_bbox(w, s, e, n)
    if not geoms:
        return None
    mask = rasterize(((g, 1) for g in geoms), out_shape=(CELLS, CELLS),
                     transform=transform, fill=0, dtype="uint8").astype(bool)
    if lakes is not None and mask.any():
        lg = lakes.in_bbox(w, s, e, n)
        if lg:
            mask &= ~rasterize(((g, 1) for g in lg), out_shape=(CELLS, CELLS),
                               transform=transform, fill=0, dtype="uint8").astype(bool)
    return mask if mask.any() else None


def read_tile_radiance(src, w, s, e, n):
    """Average atlas radiance onto the exact 400x400 tile grid. NaN where no data."""
    dst = np.full((CELLS, CELLS), np.nan, dtype=np.float32)
    rb = src.bounds
    if e <= rb.left or w >= rb.right or n <= rb.bottom or s >= rb.top:
        return dst
    # source window covering the tile (+1 px margin), clipped to the raster
    win = window_from_bounds(max(w, rb.left), max(s, rb.bottom),
                             min(e, rb.right), min(n, rb.top), transform=src.transform)
    win = win.round_offsets(op="floor").round_lengths(op="ceil")
    col0, row0 = max(0, int(win.col_off) - 1), max(0, int(win.row_off) - 1)
    col1 = min(src.width, int(win.col_off + win.width) + 1)
    row1 = min(src.height, int(win.row_off + win.height) + 1)
    win = rasterio.windows.Window(col0, row0, col1 - col0, row1 - row0)

    data = src.read(1, window=win).astype(np.float32)
    if src.nodata is not None:
        data[data == src.nodata] = np.nan
    reproject(source=data, destination=dst,
              src_transform=src.window_transform(win), src_crs="EPSG:4326",
              src_nodata=np.nan,
              dst_transform=from_bounds(w, s, e, n, CELLS, CELLS), dst_crs="EPSG:4326",
              dst_nodata=np.nan, resampling=Resampling.average)
    return dst


def write_index(out_dir):
    names = sorted(f[:-4] for f in os.listdir(out_dir) if f.endswith(".bin"))
    idx = {"version": 2, "tileDeg": TILE_DEG, "cells": CELLS,
           "sqmBase": SQM_BASE, "sqmStep": SQM_STEP, "tiles": names}
    with open(os.path.join(out_dir, "index.json"), "w") as f:
        json.dump(idx, f, separators=(",", ":"))
    return names


def sanity_checks(out_dir):
    print("\nSanity checks (tiles present in output folder):")
    for name, (lat, lon) in CHECK_POINTS.items():
        lat0 = math.floor(lat / TILE_DEG) * TILE_DEG
        lon0 = math.floor(lon / TILE_DEG) * TILE_DEG
        path = os.path.join(out_dir, tile_name(lat0, lon0) + ".bin")
        if not os.path.exists(path):
            print(f"  {name:24s} (tile {tile_name(lat0, lon0)} not generated)")
            continue
        with open(path, "rb") as f:
            v = np.frombuffer(inflate_raw(f.read()), dtype=np.uint8).reshape(CELLS, CELLS)
        cell = TILE_DEG / CELLS
        r = min(CELLS - 1, int((lat0 + TILE_DEG - lat) / cell))
        c = min(CELLS - 1, int((lon - lon0) / cell))
        val = int(v[r, c])
        if val == 0:
            print(f"  {name:24s} water / no data")
        else:
            sqm = SQM_BASE + (val - 1) * SQM_STEP
            print(f"  {name:24s} Bortle {int(decode_bortle(np.array([val]))[0])}  SQM {sqm:.2f}")


# ----------------------------------------------------------------------------- main
def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("input", help="World_Atlas_2015.tif")
    p.add_argument("--land-shp", required=True, help="Natural Earth ne_10m_land.shp")
    p.add_argument("--lakes-shp", required=True, help="Natural Earth ne_10m_lakes.shp")
    p.add_argument("--out-dir", default="LightTiles", help="output folder (default: %(default)s)")
    p.add_argument("--region", nargs=4, type=float, metavar=("WEST", "SOUTH", "EAST", "NORTH"),
                   help="only make tiles touching this lon/lat box (default: whole world)")
    p.add_argument("--skip-existing", action="store_true",
                   help="don't redo tiles already in --out-dir (resume a world run)")
    p.add_argument("--preview-dir", help="also write a colour PNG per tile here")
    args = p.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    if args.preview_dir:
        os.makedirs(args.preview_dir, exist_ok=True)
        from PIL import Image
        lut = np.array(PREVIEW_RGBA, dtype=np.uint8)

    land = LandShapes(args.land_shp)
    lakes = LandShapes(args.lakes_shp)

    w, s, e, n = args.region if args.region else (-180, -90, 180, 90)
    lat_starts = range(math.floor(s / TILE_DEG) * TILE_DEG, math.ceil(n / TILE_DEG) * TILE_DEG, TILE_DEG)
    lon_starts = range(math.floor(w / TILE_DEG) * TILE_DEG, math.ceil(e / TILE_DEG) * TILE_DEG, TILE_DEG)
    todo = [(la, lo) for la in lat_starts for lo in lon_starts]
    print(f"{len(todo)} candidate tiles")

    written = skipped_water = 0
    t_start = time.time()
    with rasterio.open(args.input) as src:
        if src.crs and src.crs.to_epsg() != 4326:
            sys.exit(f"Expected EPSG:4326, got {src.crs}")
        for i, (lat0, lon0) in enumerate(todo, 1):
            name = tile_name(lat0, lon0)
            out_path = os.path.join(args.out_dir, name + ".bin")
            if args.skip_existing and os.path.exists(out_path):
                continue
            tw, ts, te, tn = lon0, lat0, lon0 + TILE_DEG, lat0 + TILE_DEG

            mask = land_mask(land, lakes, tw, ts, te, tn)
            if mask is None:
                skipped_water += 1
                continue

            rad = read_tile_radiance(src, tw, ts, te, tn)
            valid = mask & np.isfinite(rad)
            if not valid.any():
                skipped_water += 1
                continue

            v = encode_sqm(sqm_from_mcd(np.clip(np.nan_to_num(rad, nan=0.0), 0, None)))
            v[~valid] = 0
            blob = deflate_raw(v.tobytes())
            with open(out_path, "wb") as f:
                f.write(blob)
            written += 1

            if args.preview_dir:
                Image.fromarray(lut[decode_bortle(v)], "RGBA").save(
                    os.path.join(args.preview_dir, name + ".png"))

            el = time.time() - t_start
            print(f"[{i}/{len(todo)}] {name}.bin  {len(blob) / 1024:6.1f} KB  "
                  f"land {valid.mean() * 100:5.1f}%  ({el:.0f}s elapsed)")

    names = write_index(args.out_dir)
    total_kb = sum(os.path.getsize(os.path.join(args.out_dir, f + ".bin")) for f in names) / 1024
    print(f"\nWrote {written} tiles this run, skipped {skipped_water} water/no-data tiles.")
    print(f"{args.out_dir}/ now holds {len(names)} tiles, {total_kb / 1024:.1f} MB, + index.json")
    sanity_checks(args.out_dir)


if __name__ == "__main__":
    main()
