# Release notes — 0.3.2 public-review candidate

Maintenance update for the Codex Bilingual Hover public-review candidate.

- Keeps the accessory-app overlay visible while Codex remains the active application.
- Suppresses translation while macOS or Windows native menus are open, immediately clearing stale overlays that could otherwise appear behind a menu.
- Prevents localized navigation controls from falling back to unrelated English accessibility metadata.
- Protects the host brands Codex, ChatGPT, and OpenAI from literal machine translation.
- Requires OCR text to be directly under the pointer instead of selecting nearby text.

- Provides Chinese hover translations for the Codex plugin directory and arbitrary plugin detail pages.
- Rejects normal task, chat, answer, composer, and file-preview surfaces.
- Uses exact detail actions or a `Plugins > title` breadcrumb instead of a hard-coded plugin-name catalog.
- Keeps the overlay stable within one card or text region and adapts its height to text length.
- Adds local macOS Vision OCR fallback and Windows UI Automation support.
- Bundles a universal macOS helper so public users do not need Xcode to install it.
- Adds public privacy, terms, support, security, listing, and review-test documentation.
