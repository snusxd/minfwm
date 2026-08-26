# macOS Feasibility Research

Research checked on 2026-08-26 against the linked upstream pages.

| Question | Finding | Source |
| --- | --- | --- |
| Can windows be managed without Yabai SA? | Yes. AXUIElement and AXObserver are public ApplicationServices APIs; the daemon can move, resize, hide, and observe accessible windows with Accessibility permission. | [Apple AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h) |
| Can an infinite workspace avoid native Spaces? | Yes. AeroSpace explicitly emulates virtual workspaces by moving windows and avoids native Spaces limitations. This is the closest public implementation precedent. | [AeroSpace README](https://github.com/nikitabobko/AeroSpace/blob/main/README.md) |
| Is SIP required for the baseline? | No. Yabai documents Accessibility as required and SIP changes as optional for the scripting addition's privileged WindowServer capabilities. | [Yabai requirements](https://github.com/koekeishiya/yabai/blob/master/README.md#requirements-and-caveats) |
| What is the current SA wire format? | The current Yabai source defines window move as opcode `0x06`, layer as `0x09`, and packs move coordinates as `int`; packets use a length prefix and the SA returns an acknowledgement byte. | [Yabai common.h](https://github.com/koekeishiya/yabai/blob/master/src/osax/common.h), [Yabai sa.m](https://github.com/koekeishiya/yabai/blob/master/src/sa.m#L418-L508) |

## Scope conclusion

The project is implementable on macOS 14+ with public APIs as the default.
Yabai SA remains a compatibility-checked optimization. Native Spaces,
cross-Space manipulation, and new UX features are intentionally deferred.
