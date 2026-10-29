# 2026-10-29: the dropdown render loop, the icon redraw churn, and the macOS 27 battery keys

Fixed in v3.1.1. What happened, how it was proven, and the rules that came out of it.

## Symptom

On a Mac running v3.1, the Zest menu bar icon was reported "loading and unloading" nonstop, and Zest sat at 31 to 36 percent CPU with WindowServer near 59 percent (17 percent with Zest stopped). A restart and a reboot did not help. A `sample` of Zest showed SwiftUI's AttributeGraph at the top (`propagate_dirty`, `UpdateStack::update`).

## Bug 1: an endless animation in a view that never went away

`PowerFlowView` started its dot animation in `onAppear`:

```swift
.onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
```

and the dropdown's `NSHostingController` was created once, in `StatusItemController.init`, and kept for the app's lifetime. Two things followed.

1. **The closed popover kept rendering.** NSPopover hides its window on close; it does not destroy the content. SwiftUI never sent `onDisappear`, so the repeating animation ran on, and AppKit's display-link flush laid out and rendered the hidden dropdown on every display frame (`NSWindow layoutIfNeeded` to `NSHostingView.layout()` to a full `ViewGraph` render, including a re-tile of its `ScrollView`). It started with the first click on the icon and lasted until Zest quit: measured 30.2 percent CPU for Zest and about 20 points more for WindowServer, against 0.3 percent before the click.
2. **The open popover reloaded every 1.2 s.** The endless transaction started in `onAppear` also caught the dropdown's first layout inside the popover, so the whole card collapsed and grew back from the top on every cycle. Screenshots every 0.27 s showed the cycle; with only that animation skipped, the card had 0 changed pixels. The same happened in v3.0 and v3.1.

And the animation never moved the dots: each dot sits at `((phase + i/3) mod 1) * width`, which is the same place for phase 0 and phase 1.

**Fix.** The dropdown's content is built when the popover opens and released when it closes. The dots take their position from the clock (`TimelineView(.animation(minimumInterval: 1/30, paused:))`), so nothing animates layout and the dots really travel. The Command Center window is kept between opens, so it passes its visibility in and the dots pause while it is closed (a running timeline there cost 12.2 percent CPU after close).

## Bug 2: the menu bar icon was redrawn on every state change

`StatusItemController` rebuilt and set the icon image on every `AppState.objectWillChange`. AppState forwards every service's changes (an energy sample every 12 s, device and network scans every 30 s, every new battery voltage), so the icon was replaced about seven times a minute at rest and nineteen times in the first second, nearly always with nothing visible changed. On macOS 27 each new image is rendered again by the system for every display variant of the menu bar (six on a two-display Mac), about six button draws per set.

No view wrote state while rendering: all sampled publish stacks came from timers and dispatch callbacks.

**Fix.** `MenuBarIconUpdater` compares exactly the values the renderer reads (`MenuBarIcon.Glyph`, and the optional readout title), sets the image only when the glyph changed and the title only when the readout changed, and coalesces bursts to one check per 0.25 s. The renderer takes the glyph and nothing else, so the comparison cannot drift from what is drawn; the old and new renderers draw identical pixels over 5,760 input combinations. A change of screen parameters forces one redraw, because the icon is a bitmap drawn at one scale.

## Also fixed: the dropdown size

NSPopover sizes itself from the content controller's `preferredContentSize`, which `NSHostingController` leaves at zero unless `sizingOptions` includes `.preferredContentSize`. The dropdown always opened at the popover default of 320 x 320. It now fits its content up to 640 points and scrolls beyond that.

## macOS 27 moved the battery keys

In the `AppleSmartBattery` registry entry (`ioreg -rn AppleSmartBattery -a`) on macOS 27.0.1:

| Value | Before macOS 27 | macOS 27 |
|---|---|---|
| Design capacity | `DesignCapacity` (top level) | `BatteryData.DesignCapacity` |
| Full charge capacity | `AppleRawMaxCapacity` (top level) | `BatteryData.FullChargeCapacity` |
| Battery temperature | `Temperature` (hundredths of a degree C) | gone; no live temperature key anywhere in the entry |

Zest reads the top-level keys first and the `BatteryData` keys as the fallback. The temperature comes from the battery's SMC sensors `TB0T`, `TB1T` and `TB2T`, which are 4-byte floats in degrees C on Apple Silicon. They are read through a read-only `AppleSMC` user client as the logged-in user, with no root and no helper, and the value is the median of the plausible readings (1 to 90 C; a key without a sensor reads 0). The tile says "Not available on this macOS" only after three attempts in a row found no sensor and none ever answered.

Maximum Capacity stays with `system_profiler SPPowerDataType`, the figure System Settings shows. No registry ratio reproduces it: on the Mac this was found on, Apple showed 99 percent while full charge over design gave 95 and nominal over design gave 98.

## Rules that came out of it

- Never start `withAnimation(.repeatForever)` in `onAppear`. Drive repeating motion from `TimelineView` with `paused:` tied to whether anyone can see it.
- A popover's SwiftUI content lives only while the popover is open. A hosting view kept after close keeps every animation and every `ObservedObject` update running.
- Measure CPU after closing a window or popover, not only while it is open.
- Redraw a status item only when what it shows changes; compare the renderer's own inputs.
- After a macOS upgrade, dump the registry entries an app reads (`ioreg -rn <class> -a`) and diff the key list before trusting a "--".
- To prove a visual fix, record the real app and diff frames; a unit test harness did not reproduce the popover reload in six variants.
