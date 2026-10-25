# Measuring Tool

A tiny native macOS app for quick measurements from photos. Import an image, set the scale by
drawing a line over something of known length, then measure anything else in the same plane.

- About 1 MB, no dependencies, works offline
- Opens JPEG, PNG, HEIC/HEIF, TIFF, GIF, BMP, WebP and most camera RAW files, and respects the
  photo's orientation
- Requires macOS 14 (Sonoma) or later

## Using it

1. **Import**: click Import (⌘O), drag an image onto the window, or paste one (⌘V).
2. **Scale**: click two points a known distance apart, for example the ends of a ruler, then type
   that distance and pick its unit.
3. **Zoom / Pan**: zoom in for accurate clicks. Measure switches on automatically after scaling.
4. **Measure**: click two points (or press and drag). The length is labelled on the image and shown
   in the ribbon. Click **Copy** (or ⌘C) to put the last measurement on the clipboard.

You can change the units at any time, and re-doing the scale updates every measurement.

| Action | How |
| --- | --- |
| Zoom | Pinch, scroll wheel, ⌘-scroll, ⌘= / ⌘- / ⌘0 (fit), or the controls bottom-right |
| Pan | Two-finger scroll, drag in Zoom / Pan, hold Space and drag, or middle-drag |
| Switch tool | S (Scale), M (Measure), P (Zoom / Pan) |
| Straight lines | Hold Shift to snap to 45° |
| Undo a line | Delete removes the last measurement; Esc cancels the one in progress |
| Start over | Clear removes all measurements |

### Getting accurate results

- Measurements are only right for things on the same flat surface as the scale reference, in a
  photo taken square-on. Anything at an angle or at a different distance from the camera will be off.
- Use the longest reference you can and zoom in before clicking. Being 2 px off on a 1000 px
  reference is a 0.2% error; on a 100 px reference it's 2%.

## Getting the app

### Build it yourself (recommended)

You only need Apple's Command Line Tools (`xcode-select --install`), not all of Xcode.

```sh
./build-app.sh
open "build/Measuring Tool.app"
```

Drag `build/Measuring Tool.app` to Applications to keep it. Apps you build yourself open without
any Gatekeeper warning.

To work on the code in Xcode, open `Package.swift` and press Run.

### Download a build

Every push is built by GitHub Actions. Open the latest run on the **Actions** tab and download the
`Measuring-Tool` artifact (a universal app for Apple silicon and Intel). The app isn't notarized,
so macOS blocks it the first time: open it once, then go to **System Settings → Privacy & Security**
and click **Open Anyway**. Or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/Measuring Tool.app"
```

## Project layout

```
Sources/MeasuringTool/
  MeasuringToolApp.swift  app entry point and menu commands
  ContentView.swift       window layout, status bar and the Set Scale sheet
  RibbonView.swift        the toolbar ribbon
  CanvasView.swift        image display, zoom/pan, point picking and drawing (AppKit)
  Workspace.swift         image, scale and measurements
  LengthUnit.swift        units, formatting and parsing
  ImageLoader.swift       image decoding via ImageIO
Tests/MeasuringToolTests/ unit tests, plus snapshot renders of the window
Support/Info.plist        app bundle metadata used by build-app.sh
```

Run the tests with `swift test` (needs Xcode). Set `SNAPSHOT_DIR=/some/folder` to also render
PNG snapshots of the window.
