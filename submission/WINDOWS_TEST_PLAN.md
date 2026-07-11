# Windows 10/11 final test plan

Run every case on one Windows 10 machine and one Windows 11 machine using the production ChatGPT desktop app. Record the OS build, ChatGPT version, plugin version, result, screenshot, and any Windows Defender or SmartScreen prompt.

## Installation and lifecycle

1. Install the plugin from the Git marketplace.
2. Ask Codex to install and start the helper.
3. Confirm the PowerShell process runs hidden and `status` reports `running`.
4. Enable launch at login, sign out and back in, and confirm the helper starts.
5. Disable launch at login and confirm the startup shortcut is removed.
6. Uninstall and confirm `%LOCALAPPDATA%\CodexHoverTranslator` and its startup shortcut are removed.

## Plugin surfaces

1. Hover over at least five English cards on the plugin directory.
2. Confirm the overlay appears after about 0.2 seconds.
3. Move inside one card and confirm the overlay does not repeatedly reopen.
4. Visit at least five previously unvisited plugin detail pages.
5. Hover titles, examples, short descriptions, and long descriptions.
6. Confirm detection does not depend on a known plugin-name catalog.

## Rejection surfaces

1. Move over the task composer, user messages, assistant answers, and file previews.
2. Confirm no overlay appears on any normal task/chat surface.
3. Open another desktop application and confirm the helper does not translate it.

## Limit and safety cases

1. Confirm an elevated/admin window is not silently read by the non-elevated helper.
2. Confirm unknown Windows phrases show the offline fallback rather than making a network request.
3. Test 100%, 125%, 150%, and 200% display scaling.
4. Test one and two monitors when available.
5. Test light and dark appearance.

The GitHub `windows-static` job verifies PowerShell syntax and policy markers, but it does not replace these interactive Windows 10/11 tests.

