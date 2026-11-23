# Mouse and trackpad profiles

Open **Mouse & Trackpad** and select **Global** to edit the existing defaults. Add an app to the profile picker and select it to show its overrides. Each override can inherit independently. Removing a profile restores the global behavior in that app.

- **Wheel direction** uses the global direction, the direction macOS delivers, or the reverse direction, independently on each axis.
- **Lines per notch** changes wheel distance and can activate linear scrolling for the app while the global switch is off.
- **Scroll speed** overrides the modifier-held multiplier, using the modifier selected in Global. Choose **Off** to suppress the shortcut in that app.
- **Mouse acceleration** uses the global choice, the macOS device setting, or linear pointer movement for the foreground app.

Wheel overrides follow the destination under the pointer, and existing per-feature mouse exceptions take precedence. Both the raw wheel tap and the smooth-scroll path use the profile. Acceleration follows the foreground application and uses the existing per-device mouse recovery journal to restore system values when leaving an app with a linear profile. These controls apply to mice handled by the existing services. Trackpad gestures retain their current behavior.

Feature switches in the feature menu still govern availability. These profiles use Vorssaint's existing settings key and preserve older direction and distance entries. App-specific trackpad controls, smoothing parameters, gesture actions, and button mapping are still pending. The profile architecture does not require additional permissions beyond those already used by the underlying features.
