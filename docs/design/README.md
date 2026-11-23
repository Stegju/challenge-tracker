# Design reference

The source of truth for the look. `artboards/` holds one HTML file per screen, exported from the design canvas. They are design references, not code to ship: read them for exact colours, sizes, spacing, copy and layout, then rebuild in SwiftUI.

How to read an artboard file:
- Markup sits inside `<x-dc>`. Inline `style="…"` values are the real measurements, in points at a 390 × 844 iPhone frame.
- `<helmet><style>` holds shared classes: `.nt` (notched pixel corners), `.pn` (panel), `.lbl` (small label), `.btn` / `.btn2` (buttons), `.inp` (input), and the animations.
- `<sc-for>` is a loop and `<sc-if>` a conditional; `{{name}}` values come from `renderVals()` in the `<script type="text/x-dc">` block at the bottom. That script is the reference logic for sample data, the This week panel, the barbell and the two-tap finalize.
- `<dc-import name="Mascot" mood="pumped" size="132">` embeds `Mascot.dc.html`; same for `Barbell`.
- Ignore `support.js` and the scanline and background `div`s with `aria-hidden`; those are just atmosphere (see below).

| Artboard | Screen |
|---|---|
| Main.dc.html | Home (has an `endOfMonth` prop that shows the next-month card) |
| Year.dc.html | Year |
| Pick.dc.html | Choose a challenge (New / Redo tabs) |
| Challenge.dc.html | Challenge detail |
| Stats.dc.html | Stats |
| Import.dc.html | Import (v1.1) |
| Exercises.dc.html | Exercises found (v1.1) |
| Settings.dc.html | Setup |
| Widget.dc.html | Medium widget |
| Kit.dc.html | Palette, slot states, meters, mascot moods, barbell examples |
| Mascot.dc.html, Barbell.dc.html | Components |

## Tokens

| Token | Value |
|---|---|
| background | `#0D1118` |
| panel | `rgba(18,24,34,0.92)` with a 2 pt inner border `#232C3B` |
| input / meter track | `#0A0D12` |
| text | `#E6EDF3`, strong `#FFFFFF`, muted `#8794A6`, dim `#6F7C8E`, very dim `#4D5869` |
| accent (lime) | `#C6FF3D`, text on lime `#0B0E13` |
| plates | white `#F2F2F2`, green `#3ECF6A`, yellow `#F5D33B`, blue `#3D8BFF`, red `#FF4D4D` |
| alert / boss | red `#FF4D4D`, text `#FF8A8A` |
| redo | yellow `#F5D33B` |
| info (Watch, HealthKit) | blue `#3D8BFF`, text `#7FB2FF` |

- Fonts (both free, OFL licence, from Google Fonts; bundle the .ttf files in the app): **Silkscreen** for small uppercase labels (10 pt, letter-spacing 1) and headings (bold 18 to 22 pt); **VT323** for body text and all numbers (18 to 24 pt body, 36 to 52 pt big numbers).
- Corners: no rounded corners. Panels and buttons use a stepped notch: cut a 2 × 2 pt step at 6 pt from each corner (see `.nt` clip-path). Build one `NotchedRect: Shape` and reuse it.
- Spacing: screen padding 16, panel padding 12 to 16, gaps 10 to 14. Touch targets at least 44 pt.
- Score meter: track 16 pt, fill made of plate-colour bands across the 0 to 120 range (each band 20 pts wide on the scale, red from 80 up), thin dark 1 pt dividers every 6 pt, white 2 pt tick at 100.

## Atmosphere (behind content, subtle)

- Three cool ceiling-light bars at the top (`#D7ECFF`, 40% opacity, soft glow).
- Rubber floor grid in perspective at the bottom (2 pt lines `#18202D`, 40 pt cells, 60% opacity).
- Plate trees in the bottom corners at 18% opacity (pixel art).
- A few drifting chalk-dust specks.
- Faint scanlines over everything (1 pt dark line every 3 pt, 10% opacity).
- Neon "2027" sign on Home flickers every ~7 s.
- Motion: mascot hops (pumped, on fire), bobs (steady, tired), sways (slumped); current month cell pulses. **All motion stops under Reduce Motion.**

## Mascot sprites

`mascot.json`: for each mood, a 40 × 40 grid (`rows[y][x]`, `.` = transparent) and a palette mapping letters to hex colours. `slumped` is drawn rotated −8° around (20, 38). Render with a SwiftUI `Canvas` filling 1 × 1 cells scaled up, with antialiasing off so the pixels stay crisp.
