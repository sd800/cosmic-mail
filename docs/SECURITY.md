# Security design

Cosmic Mail treats every mail file, attachment, sender name, header, and link as untrusted data.

## Isolation

The shipped app is signed with App Sandbox and user-selected file access. It has no broad home-folder, camera, microphone, contacts, or mail-account entitlement. The client-network entitlement is required by macOS to launch WebKit's subprocesses, including for local HTML. It is not used to fetch mail or remote content.

Before display, mail HTML is reconstructed with a small static tag/style allowlist. There are no source `style` blocks, scripts, event handlers, forms, SVG, embedded objects, arbitrary URI schemes, CSS URLs, font downloads, frames, or source resource attributes. Remote images are omitted. Only bounded, validated, single-frame CID PNG/JPEG/GIF attachments can become inline images.

The generated document applies a restrictive CSP, including `default-src 'none'`, `script-src 'none'`, `connect-src 'none'`, and `img-src data:`. WebKit content JavaScript and script-created windows are disabled. An independently compiled resource barrier blocks HTTP/HTTPS/WebSocket/FTP/file requests and is installed before mail loads. Failure to compile the barrier falls back to escaped plain text. The WebKit data store is ephemeral. App-owned appearance JavaScript contains only a fixed light/dark enum.

All source anchors become random opaque IDs. Navigation is cancelled before the native action runs. HTTP/HTTPS destinations are displayed for explicit confirmation; mailto stays inside capture; tel/sms can only be copied. Credentials embedded in URLs and control characters are rejected. There is no browser automation, command execution, scripting bridge, or arbitrary application-protocol launching.

## File handling

Attachments remain data until a user explicitly saves via NSSavePanel. They are never executed, automatically opened, unarchived, or written into a guessed path. Source filenames are normalized. An exported attachment may itself be unsafe in another application: saving does not certify its contents. Source messages are never modified.

MIME nesting/work/part limits, CFB bounds and cycle checks, message-size limits, archive limits, and image dimension limits constrain malformed input. Indexing is cancellable; stale selections cannot replace the current message. Limits reduce resource-exhaustion risk; they are not a proof that every malicious input is harmless.

## Verification and reporting

Run `scripts/test.sh` before releases. Check the sandbox signature, a synthetic HTML message with attempted active/remote resources, external-link confirmation, mailto capture, attachments, and archive navigation in the actual release bundle. Never include real mail in fixtures, screenshots, diagnostics, or the repository. Report vulnerabilities privately to the maintainer through the contact information at [Songming.org](https://songming.org), without attaching private mail to a public issue.
