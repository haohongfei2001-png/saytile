# Saytile Color Exploration
Date: 2026-11-07 · Candidate values are design proposals, not sampled values from competitor brands.

## Five genuinely different directions

| Direction | Primary | Dark ink | Surface | Character | Main risk |
|---|---|---|---|---|---|
| 01 Persimmon / Porcelain | #E9654B | #24272B | #F7F4EF | Human, expressive, memorable | Warm orange category is crowded; must avoid mymind-like generic orange |
| 02 Cobalt / Chalk | #4E63D8 | #202331 | #F5F6FA | Precise, confident, digital | Too close to familiar AI/Linear blue-violet territory |
| 03 Deep Teal / Citrus | #0C716C | #1E2929 | #F4F5EF | Calm, distinctive, quietly energetic | Citrus accent can feel like a productivity dashboard |
| 04 Aubergine / Apricot | #69436F | #29232D | #F8F2EC | Editorial, intimate, premium | Purple is common in AI; requires a non-neon treatment |
| 05 Vermilion / Mineral | #C94E3B | #25292A | #F2F0EA | Crafted, confident, tactile | Can feel heritage/editorial rather than contemporary software |

## Recommended direction: 01 Persimmon / Porcelain
Primary brand accent: `#E9654B` (RGB 233, 101, 75; HSL 11.6°, 78.4%, 60.4%).
Display P3 starting point: sRGB source color converted through a color-managed asset pipeline; do not simply reuse the hex as an unverified P3 tuple.
Ink: `#24272B`; warm surface: `#F7F4EF`; quiet surface: `#EFEBE5`; secondary text: `#74736F`; divider: `#E4DED6`.

Why: the product is about human expression, not model power. Persimmon offers a recognizable warm signal against the cool monochrome macOS environment, without adopting the familiar blue-violet AI palette. It should be concentrated in the brand mark, selected actions, and restrained website moments—not used as a large panel background.

## State colors are separate
- Listening: a small neutral/green activity indicator with explicit accessible text.
- Transcribing/revising: subtle ink-level activity cue; never the brand accent as a progress meter.
- Paused: neutral gray.
- Needs attention: amber.
- Error: restrained red.
- Brand identity remains Persimmon in all states; state must never recolor the logo.

## Light and dark mode
Light: porcelain surfaces, ink text, persimmon accent used sparingly.
Dark: deep graphite surface `#1F2226`, text `#F2F0EC`, muted text `#A7A39D`, persimmon adjusted only if contrast testing requires it.
The accent is not approved for small text until WCAG contrast is tested against each actual surface.
