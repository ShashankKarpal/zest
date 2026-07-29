# Zest brand

The mark is called **the Cell**. A battery cell whose charge is cut on a single diagonal, so the fill line reads as both a level and a lightning slash. One shape says both things the product cares about: how much, and how fast.

Everything here inherits `design/tokens.json` and the account palette. Zest shares mint with helios by design; the symbol, not the colour, carries identity.

---

## Construction

The symbol is drawn on a **96 unit grid**.

| Element | Geometry |
|---|---|
| Cap | x 40 to 56, y 10 to 18, radius 4 |
| Body | x 28 to 68, y 18 to 78, radius 10, stroke 8, no fill |
| Cavity | x 32 to 64, y 22 to 74 |
| Charge | cavity inset by a 3 unit moat, top edge from (35,50) to (61,32), bottom corners radius 3 |
| Optical centre | 48, 44 |

**The one deliberate inconsistency.** In monochrome the moat widens from 3 to 5 units. Without it the charge fuses into the body wall below roughly 24px and the mark reads as a solid blob. Colour keeps the tight moat; mono trades a little charge area for separation.

---

## Colour

Tokens only.

| Context | Ground | Body | Charge |
|---|---|---|---|
| Light | `bg` `#F7F5F2` | `text` `#1C1B1D` | `accent` `#1B7A55` |
| Dark | `bg` `#1C1B1D` | `text` `#F7F5F2` | `accent` `#7EE0B1` |
| Template (menu bar) | transparent | black, alpha only | black, alpha only |

The charge is always mint. Zest surfaces red and amber states in the product; the identity never does, or the icon would read as a permanent alert.

---

## Clear space and minimum sizes

Clear space on all four sides equals the cap height (8 grid units).

| Asset | Minimum |
|---|---|
| Symbol, colour | 16 px |
| Symbol, monochrome | 18 px |
| Horizontal lockup | 110 px wide |

---

## Files

```
design/
  logo/       symbol light, dark, mono black, mono white; tiles; wordmark; lockups
  app-icons/  macos/AppIcon.appiconset (10 PNGs, compiled to .icns at build time)
  menubar/    ZestTemplate.svg, .pdf, and 18pt PNGs at 1x 2x 3x, pure alpha
  github/     readme banners 1400x400, social preview 1280x640, avatar 400x400
  web/        og 1200x630, favicon set, apple touch icon, PWA icons
```

Filenames carry pixel dimensions for raster deliverables.

---

## Do not

1. Do not stretch, rotate, or shear the mark.
2. Do not recolour outside the tokens above.
3. Do not add shadows, gradients, glows, or strokes.
4. Do not change the charge level or the diagonal angle; the mark is not a live battery gauge.
5. Do not use red or amber in the identity. State colours belong to the product.
6. Do not rebuild the wordmark in live type; it is outlined geometry.

---

## Rebuilding the assets

Every file is generated from the same 96 unit geometry. If the mark changes, regenerate rather than hand-editing individual sizes.

*Mark designed 2026-07-28. Built by Claude (Anthropic), directed by Shashank Karpal.*
