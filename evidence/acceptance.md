# Acceptance record — 2026-10-27

Target: Apple Silicon, macOS 15.7.1.

## Version 1.0.3

| Check | Result |
| --- | --- |
| Gradient icon with white trackpad lines | Pass — rendered from the shared icon source |
| Menu bar outline has white pixels and a transparent background | Pass — inspected the generated menu bar asset |
| Command-M on the settings window | Pass — native GUI journey |
| Restore through the native Window menu | Pass — native GUI journey |
| Command-W closes settings while the process stays active | Pass — native GUI journey |
| Dock activation policy stays regular while minimized | Pass — system process snapshot |
| Closing settings returns to menu bar mode | Pass — system process snapshot |
| Different builds retain the same certificate identity | Pass — 1.0.2 to 1.0.3 |
| Updated GUI process retains its input permission without a reset | Pass — enabled system input hook |
| Settings-window three-finger close and four-finger minimize | Pass — operator confirmed all requested controls |
| Finder and Dock icon appearance | Pass — operator confirmed the gradient design, then system icon exports confirmed the white-line revision |

The native window journey is recorded in [window-lifecycle.txt](window-lifecycle.txt).
The update journey is recorded in [persistent-signing-update.json](persistent-signing-update.json).
The update changed the code hash and retained the designated requirement. No permission was reset or granted during the update.
The local signing key stays in a separate keychain outside the repository.
The final build 5 retained the same certificate requirement and one enabled input hook without another permission grant.
The final icons appear in [Finder](finder-icon.png), [the Dock](dock-icon.png), and [the menu bar asset](menu-bar-icon.png).
macOS uses the menu bar asset as a template. Its outline appears white on dark backgrounds and dark on light backgrounds.

## Observed results

| Check | Result |
| --- | --- |
| Compile optimized native app with warnings as errors | Pass |
| Verify the app signature | Pass |
| Verify the compressed disk image | Pass |
| Launch the installed app as a standalone bundle | Pass |
| Show the five requested default rules | Pass |
| Show both modifier groups, threshold, and raise option | Pass |
| Refuse identical move and resize modifiers | Pass |
| Save a three-pixel threshold and disable the raise option | Pass |
| Restore the two-pixel threshold and original modifier groups | Pass |
| Restore and retain the five default rules across an app restart | Pass |
| Register Launch at Login with macOS | Pass — service status enabled |
| Discover the built-in trackpad through the private interface | Pass — one trackpad |
| Live tab shortcuts | Pass — operator checked |
| Fn move and Fn-Shift resize | Pass — operator checked |
| Four-finger swipe down | Pass — operator checked |
| Three-finger click after the 1.0.1 fix | Pass — operator checked after the app restart |
| Actual logout/login startup | Pending |

The native UI supplied the settings outcomes. The preference record confirmed the saved window values.
The app signature changed during development. Scoped macOS logs proved that both permission grants still referenced earlier signatures.
A per-app reset and fresh grants restored one enabled input hook. The operator then confirmed the keyboard, Fn, and swipe controls.
The command-line diagnostic can inherit its parent process's permissions. It does not prove the GUI app has access.

The physical click probe then found two causes for the remaining gesture failure:

- A three-finger press produced both left-button and right-button events. The initial app observed only the left button.
- The click and contact timestamps differed by more than nine seconds. The initial freshness check compared these separate clocks.

Version 1.0.1 observes both button paths and consumes each matching release.
It measures contact freshness with the host clock at delivery. It retains the existing trackpad clock for swipe durations.
See [the physical input samples](three-finger-click-before-fix.txt). No typed text was recorded.
After fresh grants and an app restart, the system reported one enabled input hook with the updated button mask.
The operator then confirmed that the three-finger click works. A real logout/login startup remains unchecked.

## Repeatable live scenario

1. Install the app in Applications. Grant both permissions to that installed copy. Quit BetterTouchTool.
2. Open Mini Touch Tool. Confirm that its header says **Shortcuts enabled**.
3. Open three disposable browser tabs. From the third tab, press Command-Tab. Confirm that the second tab becomes active.
4. Open three disposable iTerm tabs. Use Control-Tab and Command-Tab. Confirm next-tab and previous-tab actions.
5. Put the pointer over a background window. Hold Fn and move the pointer without a mouse press.
6. Release Fn. Confirm that window motion stops. Repeat with Fn-Shift and confirm a resize.
7. Make a three-finger physical click in the active disposable browser tab. Confirm that exactly one tab closes.
8. Put the pointer over another window. Swipe down with four fingers. Confirm that only that window minimizes.
9. Edit one shortcut. Record a different trigger, save it, and select Apply Changes. Confirm that the new trigger works.
10. Change the move modifiers and threshold. Apply the change, restart the app, and confirm that those values persist.
11. Choose Restore Defaults, then Apply Changes. Confirm the original rules and Fn controls again.
12. Enable Launch at Login. Sign out and sign in. Confirm the menu bar icon appears without a settings window.

Record the macOS version and each observed result. Keep screenshots of the selected browser tab, the resulting window,
and the restored settings. A physical gesture must come from the actual trackpad.
