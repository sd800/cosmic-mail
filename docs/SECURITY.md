# Security design

Cosmic Mail protects local email reading through macOS App Sandbox, controlled file access, passive message rendering, and deliberate copy/export controls. Mail files, headers, attachments, and links pass through validation before display or use.

## Controlled access

The app is signed with App Sandbox and accesses documents through user-selected file permissions. Access stays scoped to the selected files and their active readers. It has no broad home-folder, camera, microphone, contacts, or mail-account entitlement. The client-network entitlement supports WebKit subprocesses, including local HTML rendering; message display blocks remote resources.

Messages, archive indexes, attachments, and captured email links are held in memory. The app reads source files directly and leaves them unchanged. Reading preferences are stored separately from message content. WebKit uses a nonpersistent data store.

## Protected message display

Before display, mail HTML and CSS are reconstructed with typed allowlists. Local fonts, colors, spacing, table geometry, and bounded responsive layouts are retained. Source selectors are scoped to the message; CSS properties and values are regenerated rather than inserted verbatim. Color variables adapt authored foregrounds and backgrounds for dark reading. Scripts, event handlers, active form behavior, SVG, frames, embedded objects, CSS URLs/imports/fonts, positioning, animations, and remote resource attributes are excluded. Inert unsupported wrappers preserve their text without gaining interactive behavior. Hidden preview text stays hidden. Inline images are limited to validated, single-frame CID PNG/JPEG/GIF attachments within byte and dimension budgets.

The generated document uses a restrictive Content Security Policy, including `default-src 'none'`, `script-src 'none'`, `connect-src 'none'`, and `img-src data:`. WebKit content JavaScript and script-created windows are disabled. An independent resource barrier blocks HTTP/HTTPS/WebSocket/FTP/file requests before a message loads. If resource-rule setup is unavailable, the reader displays escaped plain text with remote content still blocked.

App-owned renderer code runs in an isolated client world. Updates receive sanitized content through structured arguments rather than interpolated scripts, while the shell's content policy stays active. Presentation identities bind links and actions to the message actually on screen, keeping a delayed event from another message separate from the current selection.

## Deliberate links and attachments

Source links become random opaque IDs and are handled through native controls. Every supported link inside a message, including website, mailto, tel, and sms links, opens a native copy-only popover. There is no direct browser or application launch action. System-delivered mailto events retain the separate capture window. URL validation rejects embedded credentials, control characters, local-file targets, and unsupported protocols. Message content has no command-execution or arbitrary application-launch interface.

Attachments stay inert in the reader. Saving requires an explicit action and a destination chosen through NSSavePanel. Filenames are normalized, and the export contains the original attachment bytes. Cosmic Mail does not automatically execute, open, or unpack attachments, and it preserves the source message. An explicit Read attached message action uses the same passive renderer in RAM, without an intermediate saved file. Embedded MSG messages have bounded nesting and work budgets. OLE and unreadable attachment records remain visible without activation; unsupported embedded objects are retained in the original message. Save/export destinations are checked against open source documents.

## Bounded file processing

Native Swift readers validate MIME structure, MSG/CFB storage chains, and mailbox records. Source files are opened nonblocking and checked as regular files through their actual descriptors before reading. Nonlocal URLs, NUL paths, pipes, devices, and invalid output types are rejected; ordinary user-selected file aliases retain their regular-file checks. Nesting, parse work, part counts, message sizes, index metadata, image dimensions, and attachment sizes have explicit limits. Compound-file readers check offsets and detect cyclic chains. [TECHNICAL.md](TECHNICAL.md) maintains the current budgets and supported format details.

Archive indexing is incremental and cancellable. Source-file identity checks detect changes during reading; presentation ownership keeps superseded selections from replacing current content. Parsing, date ordering, and cancellable recipient/body search run away from the main UI. Only one message body is searched at a time, without a persistent body index. Unreadable or oversized search omissions are counted in the interface. Original-message export is independent of the preview limit and streams through a bounded buffer to the chosen destination. A failed or cancelled export removes its temporary output and leaves an existing destination intact.

## Verification and reporting

Security checks cover passive HTML reconstruction, remote-resource blocking, malformed file structures, image validation, copy-only links, and attachment handling. Use small synthetic fixtures and the focused procedures in [QA.md](QA.md), and verify the sandbox signature for an app release. Retain reusable test code and concise findings, with private mail and full logs excluded from test artifacts and the repository.

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/sd800/cosmic-mail/security/advisories/new). Include the affected version and a minimal synthetic reproduction; keep private mail and credentials out of public issues.
