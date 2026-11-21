# Light-pollution tiles

`make_light_tiles.py` turns the World Atlas of Artificial Night Sky Brightness
(Falchi et al. 2016, CC BY-NC 4.0, doi:10.5880/GFZ.1.4.2016.001) into 5°x5° tiles
for the Stargazing Spots feature. You only need this to regenerate tiles.

Inputs (not in git, download separately):
- World_Atlas_2015.tif (GFZ Data Services, 2.9 GB)
- Natural Earth 10m `ne_10m_land` and `ne_10m_lakes` shapefiles

```
pip install rasterio pyshp pillow numpy
python make_light_tiles.py World_Atlas_2015.tif --land-shp ne_10m_land.shp --lakes-shp ne_10m_lakes.shp --skip-existing
```

Output: `LightTiles/` (~1,130 tiles, ~11.5 MB, + index.json).
- Copy the whole folder (all .bin files + index.json) into the app's
  `StargazingSpots/LightTiles/` — everything is bundled.
