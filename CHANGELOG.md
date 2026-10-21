# Changelog

[简体中文](CHANGELOG_zh.md)

## 26.1020.3 — 2026-10-20

- Improve large mailbox browsing with incremental, memory-only indexing and background search.
- Keep oversized messages from interrupting the rest of an archive, and detect changed source files.
- Improve cancellation and resource handling without creating persistent mail caches.
- Keep the reading divider stable when switching messages, and slightly widen the message list within the existing window.

## 26.1020.2 — 2026-10-20

- Show explicit UTC offsets for email dates, preserving the sender’s stated time zone without ambiguous abbreviations.
- Simplify email-link capture headings and move the unsent-status line beside the privacy note.
- Improve app packaging reliability.
- Match the message background to the native reading area in light and dark modes.
- Remove duplicate copyright text from the About window.

## 26.1020.1 — 2026-10-20

- Introduce Cosmic Mail for macOS, with native mailto capture, local email reading, and mailbox archive browsing.
- Support EML/EMLX, Outlook MSG/OFT, MBOX-style archives, and Maildir.
- Add light/dark appearance, English/Simplified Chinese, adjustable reading text, message details, attachment saving, and original-message export.
- Add layered content isolation, bounded parsing, and explicit external-link confirmation.
- Provide a universal Apple Silicon/Intel app.
