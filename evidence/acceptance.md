# Acceptance record — 2026-10-27

Target: Apple Silicon, macOS 15.7.1.

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
| Live keyboard and physical gesture actions | Pending |
| Actual logout/login startup | Pending |

The native UI supplied the settings outcomes. The preference record confirmed the saved window values.
The app signature changed during development, so the final build needs fresh permission grants.
The command-line diagnostic can inherit its parent process's permissions. It does not prove the GUI app has access.

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
