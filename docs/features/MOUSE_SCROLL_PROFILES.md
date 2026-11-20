# Per-app scroll direction

On **Mouse & Trackpad → Scrolling**, expand **Per-app scroll direction**, add an application, and edit either axis. Each axis can inherit Vorssaint’s global direction, use the direction macOS delivers, or reverse it. The profile takes effect for mouse-wheel events routed to that app. Existing exclusion lists still take precedence, and gesture-based trackpad scrolling follows the existing handling.

The existing pointer-target cache resolves bundle identifiers off the event callback. With no matching profile, the existing global settings apply. With a match, both the raw wheel tap and the smoothing path resolve the same two axes. A reversed profile can keep the direction tap active when the global switches are off. Disabling the Scroll Direction feature suspends its overrides.

Profiles are portable settings. No new permission is requested beyond the existing Accessibility permission for mouse-wheel customization. Physical app switching and wheel versus trackpad behavior still need GUI verification.
