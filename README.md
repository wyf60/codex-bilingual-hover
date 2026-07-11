# Codex Bilingual Hover

Codex Bilingual Hover adds a Chinese/English hover overlay to the Codex plugin directory and plugin detail pages. It is designed for people who want to understand English plugin descriptions without translating ordinary task or chat content.

## Highlights

- Shows an overlay after the pointer rests on English text for about 0.2 seconds.
- Keeps the overlay stable while the pointer stays in the same card or text region.
- Supports plugin directory cards and arbitrary plugin detail pages without a hard-coded plugin-name catalog.
- Rejects normal task, chat, composer, answer, and file-preview surfaces.
- Uses local macOS Vision OCR as a fallback for inaccessible detail-page text.
- Uses Windows UI Automation and an offline dictionary on Windows.
- Does not patch or inject code into ChatGPT or Codex.

## Platform requirements

- macOS 15 or later. Accessibility permission is required; Screen Recording is optional but needed for the local OCR fallback.
- Windows 10 or 11 with Windows PowerShell 5 and the standard .NET desktop components.

## Install from a Git marketplace

Run:

```bash
codex plugin marketplace add wyf60/codex-bilingual-hover
codex plugin add codex-bilingual-hover@codex-bilingual-hover
```

Then start a new Codex task and ask Codex to install and start the hover translator. The skill uses the bundled platform helper and explains any permission that requires your approval.

## Privacy

The helper reads only UI text or the small on-screen region currently under the pointer. It does not include telemetry or an external translation service. See [PRIVACY.md](PRIVACY.md) for the full permission and data-handling explanation.

## Documentation

- [Privacy policy](PRIVACY.md)
- [Terms](TERMS.md)
- [Support](SUPPORT.md)
- [Security](SECURITY.md)
- [OpenAI submission materials](submission/)

## Development

The macOS helper source is under `plugins/codex-bilingual-hover/skills/manage-bilingual-hover/scripts/hover-helper`. The Windows implementation is the adjacent PowerShell script. Generated Swift build directories are intentionally excluded from Git.

## License

MIT
