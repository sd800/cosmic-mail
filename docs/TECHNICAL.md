# Technical guide

## Project map

- `Sources/CosmicMail/`: native SwiftUI/AppKit interface, app lifecycle, explicit file access, settings, and WebKit bridge.
- `Sources/MailCore/`: Foundation-based message models, MIME/EMLX, streaming MBOX/Maildir indexing, bounded CFB/MSG decoding, and allowlisted HTML reconstruction.
- `Resources/`: app icon and sandbox entitlements.
- `scripts/`: icon generation, bundle metadata, universal packaging, synthetic fixtures, and test entry point.
- `Tests/`: focused parser, isolation, and WebKit barrier regression checks.
- `dist/`, `test-dist/`, and `sidenote/`: ignored build output, reusable local test material, and internal handoff notes. Never commit real email.

## Native lifecycle

A single main window presents opened files or the most recent captured mailto link. The standard Settings scene implements ⌘,. Open (⌘O), original export (⌘⇧S), and close-all (⌘⇧W) use native commands. File-open and URL events arrive through NSApplicationDelegate. Finder and URL-scheme registrations declare alternate viewer capability; neither silently changes system defaults.

The model retains user-selected security scopes until files close. Archive loading is cancellable and runs off the main actor. Selecting a message starts a separate bounded read, guarded by a generation token so an older result cannot overwrite a newer selection. A mailto event cancels archive loading before presenting capture details. Dragged file URLs are collected as one operation.

Messages, attachments, indexes, and captured links live in process memory. The application does not import or duplicate documents into a persistent database. Reading preferences are UserDefaults values. WebKit uses a nonpersistent data store; its compiled content-blocking rules contain no mail and may be cached by the OS. Memory can be paged by macOS; the app does not claim control over OS swap, filesystem snapshots, or user-created exports.

## Readers

MIME decodes folded headers, RFC 2047 words, quoted-printable/base64, common charsets, RFC 2231 filenames, and multipart boundaries. Plain text and HTML alternatives are retained. EMLX's byte prefix bounds message data and excludes trailing Apple metadata. EMLX original export produces RFC email bytes without the EMLX wrapper.

MBOX scans 128 KiB chunks, records byte ranges and compact envelope fields, and reads the selected message on demand. Accepted envelope lines use standard weekday-style `From ` separators or `From - `. Apple mailbox packages use their `mbox` member. Maildir uses regular, nonsymlink files from `cur/new`. MBOX-like MBX/MBO files are supported, not proprietary binary mailbox databases.

MSG/OFT reads CFB FAT/miniFAT chains and property streams directly, with cycle/bounds checks. It supports Unicode/ANSI envelope text, plain/HTML bodies, transport headers, and by-value attachments. It never activates OLE objects. Compressed RTF-only bodies, embedded Outlook-message attachments, encrypted messages, PST/OST, and OLM are not decoded in this release. Such omissions must not be advertised as complete Outlook fidelity.

## Safe display and budgets

See [SECURITY.md](SECURITY.md). Limits are intentionally conservative: 32 MiB/message, 1 GiB/MBOX, 50,000 messages, 256 KiB/header block, 500 MIME parts, 16 nested parts, and a 96 MiB aggregate MIME parse-work budget. Displayed body input is capped at 4 MiB. Reconstructed HTML is capped around 8 MiB/50,000 tags. Inline raster input is limited to 4 MiB total, single frame, maximum 8192 on either side, and 12 million pixels. MSG attachment data is limited to 32 MiB total.

HTML is reconstructed from an allowlist. Mail-supplied fonts/colors/backgrounds are removed so native typography and appearance remain readable. Plain text preserves whitespace. Website links are replaced with opaque IDs and handled natively after confirmation. Mailto enters the capture view; tel/sms offer copy only. Other protocols and file URLs are excluded.

## Build and release

`VERSION` is the version source of truth. Format: `YY.MDD.NUM`; `NUM` is the release sequence for that month. Example: `26.1020.1`. Commit subjects are exactly `Release <version>`, without a body. Public changes go in bilingual changelogs. Internal implementation notes go in ignored `sidenote/`, not a second changelog.

`./scripts/build.sh` creates separate optimized arm64/x86_64 builds for macOS 14+, combines them using lipo, creates a native bundle, applies ad-hoc sandbox signing, verifies the signature, and writes a ZIP/checksum to `dist/`. There are no runtime third-party packages. `MAIL_SDK_OVERRIDE` selects another installed SDK. A macOS 26.5 SDK is preferred on this development machine to avoid prerelease macOS 27 SwiftUI macro tooling mismatches.

Release assets must come from the exact committed source. Upload the universal ZIP and SHA256SUMS.txt to the corresponding GitHub Release. Apple signing/notarization is not available; document the normal macOS Open Anyway workflow, never global Gatekeeper disabling.
