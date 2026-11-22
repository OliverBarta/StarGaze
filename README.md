# StarGaze ✦

**Collect the constellations, and help map light pollution while you do it.**

StarGaze is an iOS app built at **Hack Western 13** (Western University, November 2026). Point your phone at the sky to find and collect real constellations. Every find also takes a quick sky photo that estimates how light-polluted the sky is where you're standing. Together, players build a ground-level light-pollution map that shows everyone where the dark skies are.

---

## How a find works

1. **Point your phone at the sky.** The Stars tab draws the real constellations over the camera, right where they are, using your location, the time, and the phone's compass and motion sensors. Point at one and its mythological figure fades in over the stars: Orion the hunter, the Great Bear, Pegasus and more.
2. **Hold steady to fill the ring.** Keep a constellation in view and a ring fills around it. The phone has to be aimed up at the sky; point it at the ground and the ring drains.
3. **Press capture.** The phone counts down ("Hold still… 3·2·1") and takes one long-exposure sky photo.
4. **The photo is checked.** The phone counts the stars in the photo, and Google Gemini checks that it really is a night sky and looks for clouds, streetlights, haze, blur or the Moon.
5. **Collected.** The constellation turns gold and joins your Collection, with a toast like *"✦ Collected Orion · City sky (Bortle 8)"*. If the photo wasn't the sky (a ceiling, a wall, a screen), the find doesn't count.

**Spotted finds.** If the photo is a good, clear reading and Gemini can actually see the constellation's pattern in it, the find is upgraded to **Spotted**: a gold badge and **double points**.

> Identifying constellations uses only the phone's sensors, never AI. Gemini is just the quality check on the photo.

---

## Features

### 🔭 Stars: find and collect
- An AR sky drawn over the camera, with stick figures, star names and Stellarium artwork pinned to the real stars.
- Tap any constellation for its story, brightest stars and best viewing season.
- **Complete themed sets** (The Menagerie, Heroes & Gods, The Perseus Saga, The Great Hunt, The Zodiac Wheel) by finding 5 from each. Completing a set plays a cinematic reveal and stamps your collection cards.

### 🌃 Every find is a light-pollution reading
- The sky photo becomes a reading on a simple scale: **City, Bright suburban, Suburban, Rural or Dark sky**, with the Bortle number and a confidence level.
- These are **estimates from a handheld phone camera**, not calibrated measurements. Fewer visible stars means a brighter sky.
- Readings are only counted when conditions allow. Twilight, a moving phone, clouds, a streetlight in the frame, haze or a blurry photo mean the reading isn't counted (you still collect the constellation). A bright Moon lowers the confidence.
- Good readings are uploaded, without personal details and with the location rounded to about 1 km, to the shared light-pollution map.

### 🗺️ Light Pollution: where to go tonight
- A **heatmap** of light-pollution readings, plus tonight's **cloud cover** with an hour-by-hour slider.
- The **3 best spots within 25 km**, where the sky is both dark and clear, with the Moon, the best time to go and driving directions.
- For the demo, the map is seeded with simulated readings (see `supabase/light_readings_seed.sql`). Real players' readings are added on top.

### 🏆 Friends: a Strava for stargazing
- **Feed** of what your friends have found, where and when.
- **Weekly leaderboard** by points, including you: rarer constellations are worth more, each constellation counts once a week, and Spotted finds count double.
- **Add friends** by username.

### 🃏 Collection
Your finds as cards with rarity, points, place and date, plus completed-set stamps and Spotted badges.

---

## How it works

- **Sky positions:** each star's catalogue coordinates are converted to altitude and azimuth for your location and the current time, and refreshed as the Earth turns.
- **Pointing:** CoreMotion (gyroscope, accelerometer and compass) tracks where the phone points relative to true north and gravity, smoothed so the sky is steady. Unlike AR tracking, it doesn't need visual features, so it works against a dark sky. The drawn sky's field of view matches the camera's, so the stars line up with the picture. Targeting compares where you're aiming with each constellation's shape (its outline), not just its centre, with a small tolerance that scales with its size.
- **Artwork alignment:** each illustration is pinned to three real anchor stars and warped onto the sky, so the stars land on the figure.
- **Sky photo:** AVFoundation takes a ~1 s exposure at high ISO with focus near infinity, while CoreMotion records how much the phone moved. The AR session pauses for the shot so the camera is free.
- **Star counting:** an on-device detector built with Accelerate converts the photo to linear brightness, rejects hot pixels, subtracts the sky background and keeps point-like peaks. Streaks, lights and edges are rejected.
- **Quality check:** Google Gemini (`gemini-3.5-flash-lite`) gets the photo plus context (the target constellation and its brightest stars) and returns structured JSON: night sky or not, clouds, obstructions, and whether the pattern is visible.
- **Estimate:** the star count gives the Bortle class. Device checks (Sun below −12°, phone motion, Moon brightness) and Gemini's checks decide whether the reading counts.
- **Clouds:** live cloud-cover forecasts from Open-Meteo, combined with the readings to score the best spots.
- **Backend:** Supabase (Postgres + REST) stores profiles, follows, captures and light readings. Sign-in is Auth0, connected to Supabase via third-party auth, with row-level security on every table.

---

## Tech stack

Swift · SwiftUI · SceneKit · AVFoundation · CoreMotion · Accelerate · MapKit · CoreLocation · Google Gemini API · Supabase · Auth0

---

## Getting started

### Requirements
- Xcode 26 or newer
- An iPhone running iOS 26 (or the simulator: see below)
- A Google Gemini API key (free from [Google AI Studio](https://aistudio.google.com/apikey))
- A Supabase project, and an Auth0 application set up as a Supabase third-party auth provider

### Setup
1. Clone the repo:
   ```bash
   git clone https://github.com/OliverBarta/StarGaze.git
   ```
2. Copy `Secrets.example.swift` to `StarGaze/Config/Secrets.swift` and fill it in:
   ```swift
   enum Secrets {
       static let geminiAPIKey = "YOUR_GEMINI_KEY"
       static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
       static let supabaseKey = "YOUR_SUPABASE_PUBLISHABLE_KEY"
   }
   ```
   `Secrets.swift` is gitignored, so **never commit your keys**.
3. In Supabase, run `supabase/schema.sql`. Optionally, run `supabase/light_readings_seed.sql` for the simulated demo readings.
4. Put your Auth0 `ClientId` and `Domain` in `StarGaze/Auth0.plist`.
5. Open `StarGaze.xcodeproj`, choose your iPhone or a simulator, and press **Run**.

### Running on an iPhone
- In **Signing & Capabilities**, set **Team** to your own Apple ID (a free personal team works).
- Turn on **Settings → Privacy & Security → Developer Mode**, and trust your developer profile under **Settings → General → VPN & Device Management**.
- Allow camera and location access. Wave the phone in a figure-8 to calibrate the compass.
- Go outside after dark: before the Sun is 12° below the horizon, readings are marked "Twilight" and don't count.

### Demoing indoors
- **Profile → "Demo mode: allow indoor captures"** lets you collect constellations indoors: the ring fills at any angle, and the capture button collects instantly without a sky photo or Gemini check, so nothing is added to the light-pollution map.
- In the simulator, which has no camera or compass, the Stars tab shows a virtual sky you can drag around, and finds are collected without a photo.

---

## Credits & licences

- **Constellation illustrations** by **Johan Meuris**, via [Stellarium](https://github.com/Stellarium/stellarium-skycultures), under the [Free Art License 1.3](https://artlibre.org/licence/lal/en/). Animation frames derived from them are shared under the same licence.
- **Stars and constellation lines** from [d3-celestial](https://github.com/ofrohn/d3-celestial) by Olaf Frohn (BSD 3-Clause).
- **Light pollution atlas tiles** from the *New World Atlas of Artificial Night Sky Brightness*, Falchi et al. (2016) (CC BY-NC 4.0).
- **Weather data** by [Open-Meteo.com](https://open-meteo.com/) (CC BY 4.0).
- **Constellation descriptions and collection card images** generated with Claude (Anthropic).
- **Photo quality checks** by Google Gemini.

---

## Team

Built at Hack Western 13 by **Oliver Barta**, **Felix Hansen**, **Kenneth Wu** and **David Olayinka**.
