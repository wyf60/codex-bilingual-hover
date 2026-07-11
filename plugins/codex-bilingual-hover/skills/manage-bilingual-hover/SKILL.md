---
name: manage-bilingual-hover
description: Install, start, stop, diagnose, or remove the macOS or Windows Codex hover-translation helper bundled with this plugin. Use when the user asks to enable Chinese hover translations for English text in Codex, check translation-helper status, open macOS Accessibility permission settings, toggle launch at login, or uninstall the helper.
---

# Manage Codex Hover Translation

Use the platform-specific bundled management script. The helper reads only the accessibility/UI Automation text currently under the pointer and does not patch or inject code into Codex.

## Commands

Resolve the script relative to this skill directory and run one operation:

macOS:

```bash
scripts/manage-helper.sh install
scripts/manage-helper.sh start
scripts/manage-helper.sh stop
scripts/manage-helper.sh status
scripts/manage-helper.sh permission-settings
scripts/manage-helper.sh screen-recording-settings
scripts/manage-helper.sh enable-autostart
scripts/manage-helper.sh disable-autostart
scripts/manage-helper.sh uninstall
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\manage-helper.ps1 -Action install
powershell -ExecutionPolicy Bypass -File scripts\manage-helper.ps1 -Action start
powershell -ExecutionPolicy Bypass -File scripts\manage-helper.ps1 -Action status
powershell -ExecutionPolicy Bypass -File scripts\manage-helper.ps1 -Action stop
```

For a first-time setup, run `install`, then `start`. On macOS, if Accessibility access is missing, run `permission-settings` and tell the user to enable **Codex Hover Translator** under Privacy & Security > Accessibility. Plugin-list text uses this permission. If a detail-page paragraph is not exposed through Accessibility, run `screen-recording-settings`; enabling Screen Recording allows the optional on-device Vision OCR fallback. Never approve either permission on the user's behalf. Windows uses UI Automation and does not normally need an Accessibility permission prompt; elevated/admin windows may be unreadable from a non-elevated helper.

The public package includes a universal macOS helper, so `install` should use that bundled app and must not require Xcode. The Swift source remains bundled for inspection and reproducible development. Do not download or execute a replacement helper from the internet.

Run `enable-autostart` only when the user asks for launch-at-login behavior. Run `uninstall` only on an explicit removal request.

## Expected behavior

- The macOS helper shows a menu-bar item labeled **译**. The Windows helper runs as a hidden PowerShell/WPF process.
- It shows the translation overlay after the pointer rests over English text for about 0.2 seconds.
- The overlay height follows the wrapped Chinese and source-text line count, with a compact minimum for short labels and a capped maximum for long descriptions.
- It targets the Codex plugin directory and plugin detail pages by default. Normal task/chat pages do not trigger translation.
- Plugin detail detection uses exact detail actions or a `Plugins > title` breadcrumb rather than a hard-coded plugin-name catalog. Task/chat chrome is rejected before plugin signals are evaluated.
- Detail-page descriptions up to 1,200 characters are eligible for translation; the larger tooltip shows more lines for long descriptions.
- On macOS, inaccessible detail-page text can fall back to local Vision OCR when Screen Recording permission is already enabled. OCR images and recognized text remain on-device.
- The helper contains no telemetry and does not send UI text or screenshots to a developer-controlled service. macOS may download Apple language resources through the operating system.
- After a plugin card or text region activates, the overlay stays in place while the pointer remains in that region. Leaving the region is required before another overlay can activate.
- macOS uses Apple's system Translation framework for phrases outside the bundled instant dictionary. The first English-to-Chinese use may download language resources.
- Windows uses the bundled offline plugin dictionary by default. Unknown phrases show as not yet translated rather than uploading UI text to a third party.
- macOS requires macOS 15 or later and Accessibility permission. Windows requires Windows 10/11 with Windows PowerShell 5 and .NET Framework 4.8 components normally included with the OS.

## Troubleshooting

- If `status` says the app is running but no tooltip appears, verify Accessibility permission, then restart the helper.
- If the pointer is over an image or a custom control with no accessibility text, explain that there is no readable string to translate.
- If translation reports missing language resources, keep the Mac online temporarily and retry.
- If plugin-list text works but detail-page paragraphs do not, check `status`. When `screen-capture: false`, open Screen Recording settings and add the current helper app; a newly rebuilt ad-hoc-signed helper may need to be removed and re-added.
- If the user requests text embedded directly into Codex's plugin list, explain that Codex plugins do not expose host-UI injection; this helper provides an external overlay instead.

Keep user-facing instructions concise and report the exact command result when diagnosing failures.
