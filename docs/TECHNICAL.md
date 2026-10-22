# Technical guide

## Project map

- `Sources/CosmicMail/`: native SwiftUI/AppKit interface, app lifecycle, explicit file access, settings, and WebKit bridge.
- `Sources/MailCore/`: Foundation-based message models, MIME/EMLX, streaming MBOX/Maildir indexing, bounded CFB/MSG decoding, and allowlisted HTML reconstruction.
- `Resources/`: app icon and sandbox entitlements.
- `scripts/`: icon generation, bundle metadata, universal packaging, synthetic fixtures, and test entry point.
- `Tests/`: focused parser, isolation, and WebKit barrier regression checks.
- `dist/`: generated application and release packages.
- `test-dist/`: reusable synthetic test material, excluded from publication. Keep real email out of the repository.

## Native lifecycle

Menu commands use the corresponding macOS system symbols when available, with native menu rendering and keyboard shortcuts. Custom menu artwork is not used. Close all files follows the system Close command in the File menu.

Opening another document appends a separate sidebar item; earlier documents stay open, and complete unchanged file indexes are reused when reopened. Mail selection is remembered per sidebar item in RAM. Items have an individual Close file context action. Only an actual main-window close, explicit close-all, or application termination clears the session; a SwiftUI view disappearance/reparenting is not used as a document-close signal.

A single main window presents opened files or the most recent captured mailto link. The standard Settings scene implements ⌘,. Open (⌘O), original export (⌘⇧S), and close-all (⌘⇧W) use native commands. File-open and URL events arrive through NSApplicationDelegate. Finder and URL-scheme registrations declare alternate viewer capability; neither silently changes system defaults.

The model retains user-selected security scopes until files close. Archive indexing, message parsing, and search use separate serial background lanes. Cooperative cancellation drops superseded queued work and prevents stale results from replacing current content. File security scopes are shared by collections and in-flight workers, and released after their last owner closes. Reading switches retain the last completed presentation while a replacement is parsed. A new identity is published only with complete mail/rendered data; nil, oversized, and failed selections explicitly clear stale content. A loading line is delayed by 200 ms, rather than replacing the reader with a spinner on every click. Toolbar membership follows the open document, not transient message availability. During pending reads, message actions are gated; link callbacks carry the applied presentation identity and attachment saves verify membership in the current message.

The reading WebKit instance loads an empty local shell only once, after the independent resource barrier is ready. Subsequent messages replace sanitized body nodes through fixed app-owned code in WebKit's isolated client world, with structured data arguments. CSP and disabled content JavaScript remain unchanged. Appearance and font-size updates do not replace the body or reset selection/scroll. One in-flight update coalesces pending replacements; teardown and process/navigation failure invalidate callbacks without automatic reload loops. Failed reading views expose an explicit retry; dismissing the alert does not hide the failure state, and obsolete view failures cannot affect a newer presentation. No web snapshots, additional web views, disk mail caches, or persistent rendering databases are used.

A mailto event cancels archive loading before presenting capture details. Dragged file URLs are collected as one operation.

Messages, attachments, indexes, and captured links live in process memory. The application does not import or duplicate documents into a persistent database. Reading preferences are UserDefaults values. WebKit uses a nonpersistent data store; its compiled content-blocking rules contain no mail and may be cached by the OS. macOS manages memory paging and filesystem snapshots; explicit exports use the destination chosen by the user.

## Readers

MIME decodes folded headers, RFC 2047 words, quoted-printable/base64, common charsets, RFC 2231 filenames, and multipart boundaries. Plain text and HTML alternatives are retained. EMLX's byte prefix bounds message data and excludes trailing Apple metadata. EMLX original export produces RFC email bytes without the EMLX wrapper.

MBOX makes one sequential scan in 128 KiB chunks. Header fields are collected during that scan, without reopening or rereading each message. Only bounded prefixes of body lines are retained, so a very long attachment line does not grow the scanner buffer. Valid message headers corroborate weekday-style `From ` / `From - ` envelopes; bounded, unambiguous Content-Length fields protect body-contained separators. Apple mailbox packages use their `mbox` member. Maildir enumerates regular, nonsymlink files from `cur/new` without first materializing/sorting all paths. MBOX-like MBX/MBO files are supported, not proprietary binary mailbox databases.

The first completed entry is delivered immediately, then incremental batches are throttled to approximately 150 ms. A coalescing RAM mailbox prevents per-message main-thread tasks or repeated full-index snapshots. Messages can be read while indexing continues. Search is debounced and runs off the main actor; current indexed entries remain the search scope while loading continues. Date labels use a bounded RAM cache. Selecting a message uses its array position rather than a linear ID lookup.

There is no MBOX file-byte ceiling: file size does not dictate how much data must be held in RAM. Indexing stops gracefully at 200,000 entries per collection or a shared accounted metadata budget of 64 MiB across open collections. Field lengths are bounded. The UI explicitly labels partial indexes after a budget limit, cancellation, or failure. These budgets account for index metadata and work; process memory also includes object overhead, transient arrays, the selected message, and WebKit. Messages over 32 MiB remain listed without parsing their bodies, instead of aborting the archive. Selected-source reads verify device/inode, size, and nanosecond modification time before and after reading. Reopen a changed source; an already-open complete, unchanged file index can be reused from RAM after an off-main-thread identity check. Maildir is re-enumerated because directory identity alone cannot validate its children. No disk index or mail-content cache is created.

The native reading split view ignores hosted-content intrinsic sizes. Its message-list width defaults to 305 pt (previously 285 pt) and follows user dragging in RAM; switching between loading, normal mail, attachments, and empty/error states does not reframe the divider. The app's existing window default/minimum sizes are unchanged.

MSG/OFT reads CFB FAT/miniFAT chains and property streams directly, with cycle/bounds checks. It supports Unicode/ANSI envelope text, plain/HTML bodies, transport headers, and by-value attachments. It never activates OLE objects. Compressed RTF-only bodies, embedded Outlook-message attachments, encrypted messages, PST/OST, and OLM are not decoded in this release.

Email dates display the original stated numeric time-zone offset as UTC+/- (including minute offsets), with seconds when present. Parenthetical abbreviations do not override a numeric offset. Original headers and exported source bytes remain unchanged.

## Safe display and budgets

See [SECURITY.md](SECURITY.md). Limits are intentionally conservative: 32 MiB/parsed message, 200,000 indexed messages/collection, 64 MiB of accounted index metadata across open collections, 256 KiB/header block, 500 MIME parts, 16 nested parts, and a 96 MiB aggregate MIME parse-work budget. Displayed body input is capped at 4 MiB. Reconstructed HTML is capped around 8 MiB/50,000 tags. Inline raster input is limited to 4 MiB total, single frame, maximum 8192 on either side, and 12 million pixels. MSG attachment data is limited to 32 MiB total.

HTML is reconstructed from an allowlist. Mail-supplied fonts/colors/backgrounds are removed so native typography and appearance remain readable. Plain text preserves whitespace. Website links are replaced with opaque IDs and handled natively after confirmation. Mailto enters the capture view; tel/sms offer copy only. Other protocols and file URLs are excluded.

## Build and release

`VERSION` is the version source of truth. Format: `YY.MDD.NUM`; `NUM` is the release sequence for that month. Example: `26.1020.1`. Commit subjects are exactly `Release <version>`, without a body. Public changes go in bilingual changelogs.

`./scripts/build.sh` creates separate optimized arm64/x86_64 builds for macOS 14+, combines them using lipo, creates a native bundle, applies ad-hoc sandbox signing, verifies the signature, and writes a ZIP/checksum to `dist/`. There are no runtime third-party packages. `MAIL_SDK_OVERRIDE` selects another installed SDK. When installed, macOS 26.5 is the default SDK selected by these scripts.

Release assets must come from the exact committed source. Upload the universal ZIP and SHA256SUMS.txt to the corresponding GitHub Release. Apple signing/notarization is not available; document the normal macOS Open Anyway workflow, never global Gatekeeper disabling.
