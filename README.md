# Tube Symphony for iPhone

A native iOS app for [Tube Symphony](https://tubesymphony.com): the live London Underground map that turns every train arriving at a station into a note.

The website already does all of this in the browser. The app exists to do it **cooler**, meaning less CPU, less heat and less battery on a phone. It also adds what only an app can do:
- audio in the background and on the lock screen;
- AirPlay;
- a proper bottom tab bar.

## Running it

You need a Mac with Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate          # writes TubeSymphony.xcodeproj from project.yml
open TubeSymphony.xcodeproj
```

In Xcode:
1. Select the **TubeSymphony** target, then **Signing & Capabilities**, and choose your team. Alternatively, put your team ID in `DEVELOPMENT_TEAM` in `project.yml` so it survives regeneration.
2. Plug in your iPhone, pick it as the run destination, and press ⌘R.

Xcode fetches MapLibre Native through Swift Package Manager the first time you build.

`TubeSymphony.xcodeproj` is generated, so it isn't committed. Change `project.yml` instead, then run `xcodegen generate` again.

## What's where

| | |
|---|---|
| `TubeSymphony/App` | App entry and tab bar; `AppModel` (shared state and which clock the map draws on); `AppConfig` (URLs, links) |
| `TubeSymphony/Data` | The bundled network: route curves and the website's rules for placing a train on them (`RouteGeometry`), and how big things are drawn at each zoom (`ZoomScale`) |
| `TubeSymphony/Live` | The Schedule feed (`ScheduleFeed`), the fleet interpolated between samples (`FleetModel`, a port of `js/stream/remote-driver.js`), line status, the hourly key |
| `TubeSymphony/Audio` | `StreamPlayer`: plays the server's HLS mix and keeps the map on the sound (a port of `js/stream/hls-audio.js`) |
| `TubeSymphony/Map` | MapLibre Native: layers for tracks, stations, trains and blips, and the loop that moves the trains |
| `TubeSymphony/Features` | The five tabs: Map, Listen, Watch, Lines, More |
| `TubeSymphony/Resources/TubeData` | Data exported from the website (see below) |
| `tools/export-tube-data` | The exporter |

## What's downloaded, and what's streamed

Bundled in the app, about 1.3 MB in total:
- **Route curves** (`routes.bin`, 0.7 MB): all 115 routes on 19 lines, exactly as the website builds them at boot. The website builds them in the browser every time it loads; the app just reads a file.
- **Drawn track** (`tracks.json`, 0.3 MB): each line's routes, deduplicated so shared trunk is drawn once.
- **Stations, line colours, carriage sizes, the phone's zoom-scale constants** (`stations.json`, `lines.json`, `scale.json`).
- **The basemap style** (`basemap-style.json`). It points at the self-hosted tiles and glyphs on tubesymphony.com.

Streamed:
- **Train positions**: `map-assets/schedule/schedule.json`, polled once a second, only while the map is on screen.
  - It carries every train as a distance along its route, the last minute of arrivals with the note each one played, and the next 15 s of predicted arrivals.
  - The website's phones instead take the WebSocket: 10 frames a second of uncompressed JSON, 252 KB/s by `docs/part2/time-lapse.md`. The file is the same data at a tenth of the rate, and gzip makes it roughly ten times smaller again.
- **Audio**: the server's HLS mix (`map-assets/hls/{normal,relax}/stream.m3u8`), played by AVPlayer. The iPhone decodes AAC in hardware.
- **Basemap tiles**: fetched as you pan, then cached by MapLibre. Bundling them is planned (see "Next steps").
- **Line status**: `api/status.php`, fetched when the Lines tab opens.

### Keeping the export up to date
Re-export whenever lines, stations or waypoints change on the website:

```bash
cd tools/export-tube-data
npm install
node export.js --app-root ../../../labs-tube-map
```

The exporter runs the website's own scripts headless, the same way `services/schedule/sim-host.js` does, and writes down the results.

It also checks its own work. It places 5,000 random trains both ways (the website's `getPositionAtDistance`, and the app's method on the exported data) and fails if any two differ by more than a metre. On the current data the mean difference is 0.1 m and the worst is 0.3 m. It saves some of those placements as fixtures, and the unit tests check the Swift port against them.

## Why it runs cooler than the website

| Website on a phone | App |
|---|---|
| ~490 stations, each a DOM marker with an HTML label, repositioned on every camera frame | Stations and names are MapLibre layers, drawn and collision-checked on the GPU |
| Each note is a new DOM element with a CSS animation of width, height and border (layout and paint every frame) | Ripples are a circle layer; nothing is laid out |
| ~1,300 carriage quads rebuilt in JavaScript every frame | Carriages are one symbol layer, updated at 10 fps zoomed out, 15 fps close in and 8 fps in Low Power Mode, and only for trains in view |
| 10 Hz uncompressed position stream | 1 Hz gzip-compressed snapshot |
| The browser draws at the screen's rate | The map is capped at 30 fps, and the train loop stops when the map is off screen or the app is in the background |
| Route curves built at every page load | Loaded from a file |

The **Clock diagnostics** switch in More shows:
- the loop's real frame rate;
- how many carriages it is drawing;
- which clock it's on;
- how far behind London it's drawing.

These make it easy to compare against Safari with Xcode's Energy gauge.

## The clock

When audio is playing, the map follows the sound, as the website's lite mode does. It draws the Schedule instant the listener is hearing, using `playingDate + anchor.offsetMs`. So a train reaches its platform, and its ripple appears, just as its note plays. With the stream's buffer, that instant is 12–15 s behind London.

When nothing is playing, the map draws live, less 2.5 s so there are always samples on both sides to interpolate between.

## Next steps

- **A Metal train layer.** MapLibre Native supports custom Metal layers (`MLNCustomStyleLayer`). The CPU would write ~450 positions per frame and the GPU would draw every carriage in one instanced call. That replaces building ~1,300 point features ten times a second, which is the loop's main cost now.
- **Bundled basemap tiles.** Zooms 0–14 of London in the app (to be measured, but likely a few tens of MB), with close-up tiles fetched on demand.
- **On-device synth.** A C++ port of the Ganymede engine (`js/audio/audio-engine.js`, with `services/audio/chromium-dsp.js` as the reference for matching Chrome's oscillators and compressor), driven by the arrival events the app already receives. The server already chooses each note (`note.step`), so the phone would play the same melody. This mode would open up the synth controls and headphone spatial audio.
- **Offline (timetable) mode.** Bundle the timetables and run the simulation on the device. Notes on random-order lines are a pure function of line, train, station and day, so they would match the live piece.
- **Parity with the website:** parallel tracks on shared corridors, 3D trains, station sounds, the sky and weather, the tour.
- **Android.** MapLibre Native Android uses the same style and data files. The C++ synth ports across unchanged.

## Suggested fixes on the website side

Found while building this. None of them is needed for the app.

1. `pausePollsForBackground()` in `js/lines/trains.js` sets `_bgPausedLivePoll` in remote mode too. As a result, a Schedule-fed phone starts polling `api/live.php` every 5–10 s after its first background/foreground cycle.
2. The Schedule WebSocket (`services/schedule/index.js`) doesn't enable `perMessageDeflate`, and phones take it at 10 Hz. Compressing it, and offering phones a lower rate, would cut their data by about 100×.
