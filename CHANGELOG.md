# Changelog

[Simplified Chinese](CHANGELOG_zh.md)

## Unreleased

- Group development scripts by build, checks, assets, fixtures, and reference updates; align build-helper paths and development documentation.

## 26.1025.17 — 2026-10-25

- Update website checks to distinguish the introductory link to the Download section from the ZIP download action.
- Publish the project under the MIT License.

## 26.1025.16 — 2026-10-25

- Make the introductory app button scroll to the website's Download section and remove its download icon; keep the actual ZIP download in the dedicated download area.

## 26.1025.15 — 2026-10-25

- Use consistent spacing between the website's header navigation links, including Privacy and GitHub.

## 26.1025.14 — 2026-10-25

- Present the website's GitHub header link as text, with typography matching neighboring navigation items on desktop and narrow screens.

## 26.1025.13 — 2026-10-25

- Add a GitHub repository link to the website header.

## 26.1025.12 — 2026-10-25

- Link the downloaded ZIP wording in the installation guide directly to the app archive, so the file can be downloaded again from the same step.

## 26.1025.11 — 2026-10-25

- Download the app ZIP directly from the website instead of sending users to a release page to choose an asset.
- Redesign Getting started as three clear installation steps with separate expandable help for first launch and optional email-link setup.
- Normalize the website's index and index.html addresses to the homepage, preserving query parameters and fragments while keeping local HTML opening available.

## 26.1025.10 — 2026-10-25

- Add a dedicated installation guide covering ZIP extraction, moving the app to Applications, the first launch attempt, and app-specific approval through macOS Privacy & Security / Open Anyway.
- Explain when first-launch approval becomes available and provide optional instructions for manually choosing Cosmic Mail as the email-link app.

## 26.1025.9 — 2026-10-25

- Add an English product website with a sky-blue palette that follows system light/dark appearance, system fonts, and interactive product previews.
- Keep the website usable by opening its HTML locally, and add GitHub Pages deployment from the web directory.
- Refresh the app icon with the website's sky-blue palette while preserving its envelope and paper geometry.

## 26.1025.8 — 2026-10-25

- Validate local inputs as regular files before reading, rejecting unsupported filesystem targets without blocking the reader.
- Check export destinations before writing and retain source-file identity checks, protecting opened mail from unintended replacement.

## 26.1021.7 — 2026-10-21

- Improve Chinese and other multibyte message decoding with tolerant charset handling, Outlook code pages, and reconstruction of split encoded headers and long attachment filenames.
- Preserve safe authored fonts, colors, spacing, widths, borders, and table layouts in HTML mail, with readable light/dark presentation instead of applying borders to every layout cell.
- Display standard HTML character entities and all supported body fragments in order, and recover more gracefully from malformed or unclosed markup while keeping scripts and remote content blocked.
- Search recipients and decoded message bodies as well as subjects and senders. Sort archives newest first by default, with an oldest-first option.
- Export original messages independently of preview-size limits using bounded streaming, while preserving source files and cancelling interrupted copies safely.
- Open attached EML and MSG messages directly as separate in-memory sidebar items. Keep unsupported embedded-object attachments visible without activating them.
- Recover missing Outlook dates and recipient information from message metadata when transport headers are absent or invalid.
- Open supported links inside mail in a native copy-only popover, keeping system-delivered email links separate from message-body links.

## 26.1020.6 — 2026-10-20

- Use native macOS menu icons for About, Open, Close all files, and Export original.
- Move Close all files below Close while preserving its keyboard shortcut.
- Refine security documentation and public guidance.
- Refine public documentation and repository maintenance.

## 26.1020.5 — 2026-10-20

- Make the second line on the app icon's paper clearer without moving the existing line positions.
- Show the app logo beside the title in both README languages.
- Use Outlook PST/OST/OLM archives consistently when describing archive formats.

## 26.1020.4 — 2026-10-20

- Prevent reading-pane and toolbar flashing when switching messages by reusing the existing local reading page.
- Apply appearance and text-size changes without rebuilding the message body or resetting its scroll position and text selection.
- Keep the previous completed message visible during a new selection's loading, then replace it when ready; ignore late results and outdated link or attachment actions after switching or closing.
- Retain opened files as separate sidebar items, remember each file's selected message, support individual file closing, and set the message list's default width to 305 pt.

## 26.1020.3 — 2026-10-20

- Read large mailbox archives incrementally, showing messages before indexing finishes and performing searches away from the main interface thread.
- Keep indexes in RAM, stop gracefully at resource limits, and label partial results. Oversized messages remain listed without interrupting the rest of the archive.
- Detect source-file changes before reading selected messages, cancel superseded work, and release file access when it is no longer needed, without creating persistent mail caches.
- Keep the reading divider stable across message, loading, and error states, and widen the message list within the existing app window.

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
