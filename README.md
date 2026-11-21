# StarGaze ✦

**Find the best place to see the stars tonight, then compete with your friends to discover them.**

StarGaze is an iOS app built at **Hack Western 13** (Western University, November 2026). It tells you *where* to go stargazing, shows you *what* you're looking at once you're there, and turns every constellation you find into progress you can share with friends.

---

## Why StarGaze

### 🌌 1. Automatically finds the best stargazing spots
Most people can't see the stars because of two things: **light pollution** and **clouds**. StarGaze maps both and does the work for you.

- **Brightness layer:** a light-pollution map of the area around you. **Brighter areas on the map mean darker skies** and less light pollution.
- **Cloud layer:** tonight's cloud cover shown in **grey**. The greyer an area, the cloudier it is.
- **Best spots, marked automatically:** where the sky is both dark *and* clear, StarGaze places **★ star markers**, so the best places to stargaze tonight stand out at a glance.

No more guessing, driving out of the city and finding a sky full of clouds.

### 🏆 2. A Strava for stargazing
Every constellation you discover counts, and your friends can see it.

- **Friends feed:** see what your friends have discovered, where and when, like a run on Strava.
- **Leaderboards:** compete with friends on how many constellations you've found this week.
- **Show off your finds:** discoveries become shareable capture cards with rarity and points, so a rare constellation from a dark-sky park counts for more than one from your backyard.
- **Add friends** by username and stay motivated to get outside.

---

## Also inside

### 🔭 Point your phone at the sky
- Hold your phone up and StarGaze draws the constellations **exactly where they are in the real sky**, using your location, the time, and the phone's compass and tilt. No photos are taken.
- Point straight at a constellation and its **mythological figure** fades in over the stars: Orion the hunter, the Great Bear, Pegasus and more.
- **Tap any constellation** for its story, brightest stars and best viewing season, powered by **Google Gemini**.

### ✨ Discover, collect and complete sets
- **Discover** a constellation by holding it in view for a moment. It's added to your **Collection** with the date and place.
- **Complete themed sets** (The Menagerie, Heroes & Gods, The Perseus Saga, The Great Hunt, The Zodiac Wheel) by finding 5 from each. Completing a set unlocks a **cinematic reveal** and stamps your collection cards.

---

## How it works

- **Sky positions:** each star's catalogue coordinates are converted to altitude and azimuth for your location and the current time, and refreshed as the Earth turns.
- **Pointing:** ARKit aligns the scene to true north and gravity, so the drawn sky matches the real one as you move.
- **Artwork alignment:** each illustration is pinned to three real anchor stars and warped onto the sky, so the stars land on the figure.
- **Light pollution:** based on the *New World Atlas of Artificial Night Sky Brightness* (Falchi et al., 2016), preprocessed into lightweight map tiles bundled with the app.
- **Clouds:** live cloud-cover forecasts, combined with sky darkness to score and mark the best spots.
- **Descriptions:** Google Gemini (`gemini-3.5-flash-lite`).

---

## Tech stack

Swift · SwiftUI · ARKit · SceneKit · MapKit · CoreLocation · Google Gemini API · Python (offline data preprocessing)

---

## Getting started

### Requirements
- Xcode with the iOS 18 SDK or newer
- An iPhone or simulator running iOS 18+
- A Google Gemini API key (free from [Google AI Studio](https://aistudio.google.com/apikey))

### Setup
1. Clone the repo:
   ```bash
   git clone https://github.com/OliverBarta/StarGaze.git
   ```
2. Copy `Secrets.example.swift` to `StarGaze/Config/Secrets.swift` and add your key:
   ```swift
   enum Secrets {
       static let geminiAPIKey = "YOUR_KEY_HERE"
   }
   ```
   `Secrets.swift` is gitignored, so **never commit your key**.
3. Open `StarGaze.xcodeproj`, choose a simulator or your iPhone, and press **Run**.

### Running on an iPhone
- In **Signing & Capabilities**, set **Team** to your own Apple ID (a free personal team works).
- Turn on **Settings → Privacy & Security → Developer Mode**, and trust your developer profile under **Settings → General → VPN & Device Management**.
- Allow camera and location access. Wave the phone in a figure-8 to calibrate the compass.

> In the simulator, which has no camera, the Stars tab shows a virtual sky you can drag around.

---

## Credits & licences

- **Constellation illustrations** by **Johan Meuris**, via [Stellarium](https://github.com/Stellarium/stellarium-skycultures), under the [Free Art License 1.3](https://artlibre.org/licence/lal/en/). Animation frames derived from them are shared under the same licence.
- **Stars and constellation lines** from [d3-celestial](https://github.com/ofrohn/d3-celestial) by Olaf Frohn (BSD 3-Clause).
- **Light pollution data** from the *New World Atlas of Artificial Night Sky Brightness*, Falchi et al. (2016).
- **Constellation descriptions** generated by Google Gemini.

---

## Team

Built at Hack Western 13 by **Oliver Barta**, **Felix Hansen**, **Kenneth Wu** and **David Olayinka**.
