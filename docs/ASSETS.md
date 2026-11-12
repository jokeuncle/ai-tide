# Original visual materials

All three shipping PNGs were generated independently with the built-in imagegen tool. They are standalone original materials, not crops from a rendered interface or screenshots of other products. SwiftUI draws the interface and Canvas draws traffic-driven particles over them.

- `Sources/Tide/Resources/jade.png`: a transparent, centered jade/opal glass sphere with fine silk currents, neutral and still; no emitted streams, UI, text or outside shadow. Used for the OpenAI client panel.
- `Sources/Tide/Resources/copper.png`: the matching transparent copper/apricot glass sphere. Used for native Claude Code.
- `Sources/Tide/Resources/app-icon.png`: an original macOS graphite squircle tile, a jade glass tide orb and a restrained copper current, designed to read at small sizes. No third-party brand logos or blue accents.

The generated materials are bundled into the application. `make-icon.sh` only resamples the icon to Apple's standard iconset sizes and packages `.icns`; it does not generate the icon's visual content. `docs/concept.png` is the earlier demonstration concept and is not an executable screen or live data. `docs/screenshot.png` is an actual running application capture.
