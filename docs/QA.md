# Verification guide

Use small synthetic inputs and run the checks relevant to the changed behavior. Parser and UI tests live in `Tests/`; `scripts/test.sh` is the full test entry point. No stress test or large archive is needed for routine maintenance.

## Message parsing and archive handling

- Check mailto decoding, folded headers, MIME alternatives, common encodings, CID images, EMLX export, and MSG/CFB bounds and cyclic chains.
- Exercise MBOX indexing with a small multi-message file, separators inside bodies, Content-Length, and a line crossing the scanner chunk boundary. Simulate index limits with small configured budgets and oversized-message behavior with metadata rather than large generated files.
- Search recipients and decoded body text, check newest/oldest date ordering without changing selection IDs, and copy a tiny original with deliberately small chunks. Cancellation must preserve an existing output; export/save must reject open-source destinations. Test export architecture without generating a large message.
- Check incremental results, cancellation, changed source files, RAM index reuse, background search, and Maildir symlink filtering. A partial or failed read must leave a clear state and a usable retry path.
- Open multiple files, switch between them, close individual files, and close all. Each open file keeps its selected message while present in the sidebar.

## Protected display

- Include attempted scripts, event handlers, remote images, frames, styles, and executable links in a synthetic HTML message. Check passive text/tables/emphasis remain readable and remote resources stay blocked.
- Verify the WebKit resource barrier compiles and the generated content policy stays installed after message replacement, appearance changes, and text-size changes.
- Confirm HTML replacements use the existing local shell. Light/dark and font-size changes preserve selection; a new message clears the previous message's selection.
- Exercise rapid selection, delayed completion, close/disposal, failed reads, and explicit retry. Stale content and actions must remain associated with their original presentation.
- Check Chinese invalid-byte recovery, split encoded words, segmented filenames, multiple inline HTML fragments, MSG codepages/FILETIME dates, and visible embedded/unavailable attachments. Use a tiny regular-sector compound fixture, not private Outlook files.
- Verify authored layout-table cells have no added borders, safe color/font rules reach computed styles, hidden preheaders stay hidden, and width-only responsive rules work. Unsafe CSS must not appear in the reconstructed stylesheet.
- Read an attached message as a RAM-only item and return to its parent. Check byte-bounded filenames preserve extensions.
- Save a tiny synthetic attachment through NSSavePanel and compare it with the source bytes. Saving must not open the attachment or another application.

## Native interface

- Check English/Simplified Chinese, automatic/light/dark appearance, system typography, headers, attachments, numeric UTC offsets, and a continuous reading background.
- Switch between HTML, plain text, attachments, loading, and empty/error states. The message list starts at 305 pt and the reading divider remains stable; switching content does not resize the window or flash the toolbar.
- Verify copy-only in-message website/mailto/tel/sms popovers and separate system mailto capture. A synthetic mailto received after closing the main window opens its details without restoring old mail.
- Check the native Open file picker, About panel, single copyright line, and Settings shortcut. File-menu Close all files follows Close, and corresponding commands use system symbols.
- Installation leaves the default-email-handler choice unchanged. Verify a handler change only through an explicit user action.

## Icons and packaging

- Generate icons from `scripts/icon.swift` and verify the `.icns` and README PNG use the same artwork. Both README headings display the generated PNG at 96 px.
- Build the universal release using `scripts/build.sh`. Verify arm64/x86_64 slices and strict App Sandbox code signing; validate the ZIP and checksum against the committed source.
- Run the relevant smoke checks against the release bundle. Track architecture-specific runtime coverage separately from universal compilation.

## Fixtures

`scripts/make-fixtures.py` creates small synthetic messages and archives in ignored `test-dist/`. Keep its local README current so fixtures can be reused for later maintenance. Retain test code, tiny fixtures, and concise findings, not full logs or recordings. Real mail and personal browser data stay outside test artifacts and the repository.
