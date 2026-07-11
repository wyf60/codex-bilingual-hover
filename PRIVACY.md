# Privacy Policy

Effective date: July 11, 2026

Codex Bilingual Hover is a local desktop helper for translating English text shown in the Codex plugin directory and plugin detail pages.

## Data collected

The plugin does not collect account information, usage analytics, advertising identifiers, or telemetry. It does not operate a developer-controlled server.

## Text and screen processing

On macOS, the helper uses Accessibility APIs to read the UI text under the pointer. When a plugin detail page does not expose text through Accessibility, the helper can capture a small region around the pointer and use Apple's Vision framework to recognize that text. Captured image data and recognized text are processed transiently on the device and are not stored by the plugin.

On Windows, the helper uses Windows UI Automation to read UI text. Translation uses the bundled offline dictionary.

The plugin does not upload UI text or screenshots to a developer-controlled service. macOS may contact Apple to download system language resources; that operating-system activity is governed by Apple's terms and privacy policy.

## Permissions

- **Accessibility on macOS:** required to read accessible text under the pointer. The helper does not use this permission to type into or click Codex.
- **Screen Recording on macOS:** used only for the on-device OCR fallback when text is inaccessible. The helper does not continuously record video or audio.
- **UI Automation on Windows:** used to read the UI element under the pointer. Elevated windows may not be readable by a non-elevated helper.

## Storage

The plugin stores only its installed helper files, optional launch-at-login configuration, and a temporary local status file. It does not create a browsing history or translation history.

## Sharing

The plugin does not sell or share user data. It does not transmit UI content to third-party translation websites.

## Changes and contact

Material changes will be documented in the repository release notes. For questions, use the support process in [SUPPORT.md](SUPPORT.md).
