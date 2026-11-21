#!/usr/bin/env python3
"""Fabricate light-pollution readings across North America for `public.light_readings`.

Writes a SQL file of inserts to paste into the Supabase SQL Editor (it runs as the
database owner, so RLS doesn't get in the way). Coordinates are stored as
point(latitude, longitude); strength is 0 (pristine dark sky) to 1 (big-city glow).

Strength is estimated from distance to major cities, weighted by population, with
brightness falling off as distance^-2.5 (Walker's law), then log-scaled to 0-1.

Usage:
    python3 supabase/fabricate_light_readings.py            # writes supabase/light_readings_seed.sql
    python3 supabase/fabricate_light_readings.py -n 3000 -o out.sql --seed 7
"""

import argparse
import math
import random
from pathlib import Path

# Coarse outline of mainland North America as (lat, lon), from Alaska's north coast
# east along the Arctic, around Hudson Bay, down the Atlantic and Gulf coasts to Panama,
# then back up the Pacific coast. Arctic islands, Greenland and the Caribbean are left out.
LAND_OUTLINE = [
    (71.3, -156.8), (70.1, -143.0), (69.6, -141.0), (68.9, -136.0), (69.4, -132.0),
    (69.8, -128.0), (68.0, -115.0), (68.6, -104.0), (67.8, -98.0), (68.5, -94.0),
    (66.5, -86.5), (63.5, -90.5), (58.8, -94.2), (57.0, -92.4), (55.2, -85.0),
    (52.0, -79.5), (55.0, -77.5), (58.5, -78.0), (62.4, -77.9), (62.0, -73.0),
    (60.0, -69.5), (60.3, -64.6), (56.5, -61.5), (53.5, -56.0), (52.0, -55.7),
    (50.2, -59.5), (50.0, -66.5), (48.8, -64.3), (46.0, -61.0), (43.5, -65.7),
    (44.0, -69.0), (42.0, -70.0), (41.0, -72.0), (40.5, -74.0), (38.9, -74.9),
    (37.0, -76.0), (35.2, -75.5), (33.8, -78.0), (32.0, -81.0), (30.4, -81.4),
    (27.0, -80.0), (25.2, -80.25), (25.9, -81.7), (27.8, -82.8), (29.9, -84.4),
    (30.4, -87.0), (29.0, -89.2), (29.6, -92.5), (29.2, -94.8), (27.0, -97.4),
    (25.0, -97.5), (22.3, -97.8), (19.2, -96.1), (18.4, -94.5), (18.6, -91.5),
    (21.3, -90.3), (21.5, -86.7), (18.5, -87.7), (16.0, -88.6), (15.8, -86.0),
    (15.0, -83.3), (11.0, -83.7), (9.5, -82.2), (9.0, -79.5), (7.2, -77.8),
    (7.2, -80.9), (8.2, -82.9), (9.6, -85.4), (11.2, -85.9), (13.0, -87.6),
    (13.9, -91.0), (14.7, -92.3), (16.0, -95.0), (15.7, -96.5), (16.7, -99.8),
    (18.2, -102.9), (19.4, -105.0), (20.6, -105.3), (22.5, -105.7), (25.0, -108.2),
    (27.9, -110.6), (29.5, -112.3), (31.6, -114.6), (28.0, -112.8), (24.2, -110.3),
    (22.9, -109.9), (24.7, -112.2), (27.8, -114.9), (30.4, -115.9), (32.5, -117.1),
    (34.0, -118.5), (34.5, -120.6), (36.6, -121.9), (37.8, -122.5), (40.4, -124.4),
    (43.0, -124.5), (46.2, -124.0), (48.4, -124.7), (50.0, -127.5), (54.5, -130.5),
    (56.5, -133.5), (58.3, -136.5), (59.9, -144.0), (60.5, -147.0), (59.2, -151.8),
    (57.0, -154.0), (55.0, -161.0), (54.6, -164.8), (55.8, -162.0), (58.6, -157.0),
    (58.8, -161.8), (60.4, -165.2), (63.0, -164.5), (64.5, -166.5), (65.6, -168.0),
    (66.9, -163.8), (68.9, -166.2), (70.6, -160.0),
]

# Rough outlines of the Great Lakes as (lat, lon), so no readings land in the water.
LAKES = [
    [(46.6, -92.0), (46.7, -90.5), (46.5, -87.5), (46.5, -85.0), (47.0, -84.7),  # Superior
     (48.0, -84.9), (48.7, -86.3), (48.8, -88.0), (48.2, -89.4), (47.5, -90.5), (46.8, -92.0)],
    [(41.7, -87.5), (42.5, -87.8), (43.5, -87.7), (44.5, -87.5), (45.8, -86.9),  # Michigan
     (45.9, -85.0), (45.0, -85.5), (44.0, -86.4), (43.0, -86.2), (42.0, -86.5), (41.7, -87.0)],
    [(43.0, -82.4), (44.0, -82.6), (45.3, -83.4), (46.0, -84.0), (46.2, -83.0),  # Huron
     (46.0, -81.5), (45.3, -80.3), (44.5, -80.0), (44.6, -81.3), (43.3, -81.7)],
    [(41.7, -83.3), (41.55, -82.5), (41.6, -81.5), (42.1, -80.2), (42.5, -79.3),  # Erie
     (42.85, -78.95), (42.6, -80.0), (42.5, -81.5), (42.0, -83.0)],
    [(43.25, -79.75), (43.3, -78.5), (43.3, -77.0), (43.5, -76.3), (44.1, -76.4),  # Ontario
     (43.95, -77.5), (43.85, -78.5), (43.6, -79.4)],
]

# (name, lat, lon, metro population in thousands)
CITIES = [
    ("New York", 40.71, -74.01, 19500), ("Los Angeles", 34.05, -118.24, 13000),
    ("Chicago", 41.88, -87.63, 9400), ("Dallas", 32.78, -96.80, 7600),
    ("Houston", 29.76, -95.37, 7100), ("Washington", 38.91, -77.04, 6300),
    ("Philadelphia", 39.95, -75.17, 6200), ("Miami", 25.76, -80.19, 6100),
    ("Atlanta", 33.75, -84.39, 6100), ("Boston", 42.36, -71.06, 4900),
    ("Phoenix", 33.45, -112.07, 4900), ("San Francisco", 37.77, -122.42, 4700),
    ("Riverside", 33.95, -117.40, 4600), ("Detroit", 42.33, -83.05, 4300),
    ("Seattle", 47.61, -122.33, 4000), ("Minneapolis", 44.98, -93.27, 3700),
    ("San Diego", 32.72, -117.16, 3300), ("Tampa", 27.95, -82.46, 3200),
    ("Denver", 39.74, -104.99, 3000), ("Baltimore", 39.29, -76.61, 2800),
    ("St. Louis", 38.63, -90.20, 2800), ("Orlando", 28.54, -81.38, 2700),
    ("Charlotte", 35.23, -80.84, 2700), ("San Antonio", 29.42, -98.49, 2600),
    ("Portland", 45.52, -122.68, 2500), ("Sacramento", 38.58, -121.49, 2400),
    ("Pittsburgh", 40.44, -79.99, 2400), ("Austin", 30.27, -97.74, 2400),
    ("Las Vegas", 36.17, -115.14, 2300), ("Cincinnati", 39.10, -84.51, 2300),
    ("Kansas City", 39.10, -94.58, 2200), ("Columbus", 39.96, -83.00, 2100),
    ("Indianapolis", 39.77, -86.16, 2100), ("Cleveland", 41.50, -81.69, 2100),
    ("San Jose", 37.34, -121.89, 2000), ("Nashville", 36.16, -86.78, 2000),
    ("Virginia Beach", 36.85, -75.98, 1800), ("Providence", 41.82, -71.41, 1700),
    ("Jacksonville", 30.33, -81.66, 1600), ("Milwaukee", 43.04, -87.91, 1600),
    ("Raleigh", 35.78, -78.64, 1500), ("Oklahoma City", 35.47, -97.52, 1400),
    ("Memphis", 35.15, -90.05, 1300), ("Louisville", 38.25, -85.76, 1300),
    ("Salt Lake City", 40.76, -111.89, 1300), ("New Orleans", 29.95, -90.07, 1300),
    ("Buffalo", 42.89, -78.88, 1200), ("Birmingham", 33.52, -86.80, 1100),
    ("Albuquerque", 35.08, -106.65, 920), ("Tucson", 32.22, -110.97, 1050),
    ("Omaha", 41.26, -95.93, 970), ("El Paso", 31.76, -106.49, 870),
    ("Boise", 43.62, -116.20, 790), ("Spokane", 47.66, -117.43, 590),
    ("Anchorage", 61.22, -149.90, 400), ("Fargo", 46.88, -96.79, 250),
    ("Billings", 45.78, -108.50, 190),
    # Canada
    ("Toronto", 43.65, -79.38, 6700), ("Montreal", 45.50, -73.57, 4300),
    ("Vancouver", 49.28, -123.12, 2700), ("Calgary", 51.05, -114.07, 1600),
    ("Edmonton", 53.55, -113.49, 1500), ("Ottawa", 45.42, -75.70, 1500),
    ("Winnipeg", 49.90, -97.14, 850), ("Quebec City", 46.81, -71.21, 840),
    ("Hamilton", 43.26, -79.87, 790), ("Kitchener", 43.45, -80.49, 620),
    ("London", 42.98, -81.25, 550), ("Halifax", 44.65, -63.57, 470),
    ("Victoria", 48.43, -123.37, 400), ("Saskatoon", 52.13, -106.67, 340),
    ("Regina", 50.45, -104.62, 260),
    ("Thunder Bay", 48.38, -89.25, 120), ("Yellowknife", 62.45, -114.37, 20),
    ("Whitehorse", 60.72, -135.06, 30), ("Fort McMurray", 56.73, -111.38, 70),
    # Mexico and Central America
    ("Mexico City", 19.43, -99.13, 22000), ("Guadalajara", 20.67, -103.35, 5300),
    ("Monterrey", 25.69, -100.32, 5300), ("Puebla", 19.04, -98.21, 3200),
    ("Toluca", 19.28, -99.66, 2400), ("Tijuana", 32.51, -117.04, 2200),
    ("León", 21.12, -101.68, 1900), ("Juárez", 31.69, -106.42, 1500),
    ("Querétaro", 20.59, -100.39, 1600), ("Mérida", 20.97, -89.62, 1300),
    ("Chihuahua", 28.63, -106.07, 990), ("Hermosillo", 29.07, -110.96, 930),
    ("Culiacán", 24.81, -107.39, 1000), ("Acapulco", 16.85, -99.82, 880),
    ("Cancún", 21.16, -86.85, 930), ("Veracruz", 19.17, -96.13, 940),
    ("Oaxaca", 17.07, -96.73, 700), ("Guatemala City", 14.63, -90.51, 3000),
    ("San Salvador", 13.69, -89.22, 2400), ("Tegucigalpa", 14.07, -87.19, 1500),
    ("San Pedro Sula", 15.50, -88.03, 1100), ("Managua", 12.11, -86.24, 1400),
    ("San José CR", 9.93, -84.08, 2200), ("Panama City", 8.98, -79.52, 2000),
]

MAX_RADIANCE = 20000  # roughly the centre of the biggest metros; maps to strength 1


def inside(lat, lon, polygon):
    """Ray-casting point-in-polygon test on (lat, lon) vertices."""
    hit = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        lat_i, lon_i = polygon[i]
        lat_j, lon_j = polygon[j]
        if (lat_i > lat) != (lat_j > lat):
            cross_lon = lon_i + (lat - lat_i) * (lon_j - lon_i) / (lat_j - lat_i)
            if lon < cross_lon:
                hit = not hit
        j = i
    return hit


def on_land(lat, lon):
    if any(inside(lat, lon, lake) for lake in LAKES):
        return False
    return inside(lat, lon, LAND_OUTLINE)


def distance_km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(a))


def strength_at(lat, lon, rng):
    # Walker's law: sky glow falls off ~ population * distance^-2.5 (offset so it's finite at 0 km).
    radiance = sum(pop * (1 + distance_km(lat, lon, clat, clon) / 10) ** -2.5
                   for _, clat, clon, pop in CITIES)
    strength = math.log10(1 + radiance) / math.log10(1 + MAX_RADIANCE)
    # small towns, highways, industry: a bit of local noise
    strength += rng.gauss(0, 0.03)
    return min(1.0, max(0.0, strength))


def random_land_point(rng):
    lat_min, lat_max = min(p[0] for p in LAND_OUTLINE), max(p[0] for p in LAND_OUTLINE)
    lon_min, lon_max = min(p[1] for p in LAND_OUTLINE), max(p[1] for p in LAND_OUTLINE)
    while True:
        # uniform on the sphere, so the far north isn't oversampled
        lat = math.degrees(math.asin(rng.uniform(math.sin(math.radians(lat_min)),
                                                 math.sin(math.radians(lat_max)))))
        lon = rng.uniform(lon_min, lon_max)
        if on_land(lat, lon):
            return lat, lon


def near_city_point(rng):
    # weight toward bigger cities, but not linearly or New York and Mexico City take everything
    weights = [math.sqrt(c[3]) for c in CITIES]
    while True:
        _, clat, clon, _ = rng.choices(CITIES, weights)[0]
        spread = rng.choice([0.15, 0.5, 1.2])  # downtown, suburbs, exurbs (degrees)
        lat = clat + rng.gauss(0, spread)
        lon = clon + rng.gauss(0, spread / max(0.3, math.cos(math.radians(clat))))
        if on_land(lat, lon):
            return lat, lon


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-n", "--count", type=int, default=2000, help="number of readings")
    parser.add_argument("-o", "--out", type=Path,
                        default=Path(__file__).with_name("light_readings_seed.sql"))
    parser.add_argument("--seed", type=int, default=42, help="random seed (same seed, same data)")
    parser.add_argument("--city-share", type=float, default=0.45,
                        help="fraction of points clustered around cities (rest spread over land)")
    args = parser.parse_args()

    rng = random.Random(args.seed)
    rows = []
    for _ in range(args.count):
        lat, lon = near_city_point(rng) if rng.random() < args.city_share else random_land_point(rng)
        rows.append((lat, lon, strength_at(lat, lon, rng)))

    lines = [
        "-- Fabricated light-pollution readings for North America.",
        f"-- Generated by fabricate_light_readings.py (n={args.count}, seed={args.seed}).",
        "-- coordinates = point(latitude, longitude); strength 0 = dark sky, 1 = city glow.",
        "insert into public.light_readings (coordinates, strength) values",
    ]
    lines += [f"  (point({lat:.5f}, {lon:.5f}), {s:.4f})" + ("," if i < len(rows) - 1 else ";")
              for i, (lat, lon, s) in enumerate(rows)]
    args.out.write_text("\n".join(lines) + "\n")

    strengths = sorted(r[2] for r in rows)
    print(f"Wrote {len(rows)} readings to {args.out}")
    print(f"strength min {strengths[0]:.2f} · median {strengths[len(rows) // 2]:.2f} · max {strengths[-1]:.2f}")


if __name__ == "__main__":
    main()
