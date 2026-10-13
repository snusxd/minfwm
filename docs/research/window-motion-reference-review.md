# Window motion references (2026-10-13)

Reviewed source revisions:

- Paneru `8a213313538a352537b26e25131cfe75f1e00724` (MIT).
- Nehir `f097f35a22c463b343c16e29327bd317b7573171` (GPL-2.0-only).

This review changed no animation implementation and copied no project code.
The immediate implementation fixes minfwm's transform cleanup and disables the
experimental backend by default; live recovery is in
[the acceptance record](../acceptance-macos.md#persistent-transform-regression-and-recovery-2026-10-13).

## Smooth movement

Paneru uses elapsed-time exponential easing for reposition/resize updates and
finishes near the target. It also distinguishes its own frame notifications
from external changes during animations. Its scoped, reference-counted
AXEnhancedUserInterface guard suppresses application-driven AX animations and
restores the previous enabled state after the final operation. This addresses
competing animations; it does not remove macOS offscreen constraints.
Sources: [animation and notification systems](https://github.com/karinushka/paneru/blob/8a213313538a352537b26e25131cfe75f1e00724/src/ecs/systems.rs),
[window AX operations](https://github.com/karinushka/paneru/blob/8a213313538a352537b26e25131cfe75f1e00724/src/manager/windows.rs).

Nehir uses time-based springs, including critically damped movement presets.
Its per-display display links sample animation at the upcoming presentation
timestamp and stop when work finishes. Those are useful design references for
consistent movement across refresh rates.
Sources: [spring implementation](https://github.com/apphane-dev/nehir/blob/f097f35a22c463b343c16e29327bd317b7573171/Sources/Nehir/Core/Animation/SpringAnimation.swift),
[display-linked scheduling](https://github.com/apphane-dev/nehir/blob/f097f35a22c463b343c16e29327bd317b7573171/Sources/Nehir/Core/Controller/LayoutRefreshController.swift).

For a future minfwm animation implementation, keep floating-point camera state
in the core, sample once per display presentation, and round only at the
backend boundary. Direct pointer movement should follow input without a second
easing writer; programmatic camera transitions can use a time-based curve.
Use readback to classify self-generated frame notifications, and cancel motion
on genuine native dragging. None of this substitutes for correct transform
ownership and cleanup.

## Offscreen constraints

Paneru explicitly retains a thin visible window sliver because fully offscreen
windows can be relocated by macOS. It also documents monitor arrangement
limitations. Its horizontal strip does not establish unrestricted vertical
placement above the menu bar.
Source: [documented limitations](https://github.com/karinushka/paneru/blob/8a213313538a352537b26e25131cfe75f1e00724/README.md#recommended-system-options).

Nehir's investigation includes failed SkyLight, shape and parking experiments.
Read its July 2026 resolution rather than treating the earlier failure log as
the final result: it keeps at least one unit inside the usable visible frame
and masks the Dock-reserved band with its own opaque panel. This solves the
documented fixed-Dock edge case. It does not provide a general mechanism for
making arbitrary third-party windows invisible to macOS or for a free 2D
canvas above the menu bar. The panel workaround also changes edge appearance
and would need an explicit product decision before adoption.
Source: [investigation and final resolution](https://github.com/apphane-dev/nehir/blob/f097f35a22c463b343c16e29327bd317b7573171/docs/offscreen-clamp-fix.md#resolution-2026-07-fixed-dock-edge-solved).

Neither reviewed approach removes the need to validate minfwm's private
translation path against native dragging, application frame changes, popup
placement, shutdown and SA replacement. Source inspection is not live
validation of those projects on this machine.
