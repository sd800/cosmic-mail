# Security design

Cosmic Mail protects local email reading through macOS App Sandbox, controlled file access, passive message rendering, and confirmed external actions. Mail files, headers, attachments, and links pass through validation before display or use.

## Controlled access

The app is signed with App Sandbox and accesses documents through user-selected file permissions. Access stays scoped to the selected files and their active readers. It has no broad home-folder, camera, microphone, contacts, or mail-account entitlement. The client-network entitlement supports WebKit subprocesses, including local HTML rendering; message display blocks remote resources.

Messages, archive indexes, attachments, and captured email links are held in memory. The app reads source files directly and leaves them unchanged. Reading preferences are stored separately from message content. WebKit uses a nonpersistent data store.

## Protected message display

Before display, mail HTML is reconstructed with a fixed tag/style allowlist. This retains readable text, tables, and emphasis while removing scripts, event handlers, forms, source style blocks, SVG, frames, embedded objects, and remote resource attributes. Inline images are limited to validated, single-frame CID PNG/JPEG/GIF attachments within byte and dimension budgets.

The generated document uses a restrictive Content Security Policy, including `default-src 'none'`, `script-src 'none'`, `connect-src 'none'`, and `img-src data:`. WebKit content JavaScript and script-created windows are disabled. An independent resource barrier blocks HTTP/HTTPS/WebSocket/FTP/file requests before a message loads. If resource-rule setup is unavailable, the reader displays escaped plain text with remote content still blocked.

App-owned renderer code runs in an isolated client world. Updates receive sanitized content through structured arguments rather than interpolated scripts, while the shell's content policy stays active. Presentation identities bind links and actions to the message actually on screen, keeping a delayed event from another message separate from the current selection.

## Deliberate links and attachments

Source links become random opaque IDs and are handled through native controls. Website destinations are shown for confirmation; mailto links stay in Cosmic Mail's capture view, and tel/sms links provide copying only. URL validation rejects embedded credentials, control characters, local-file targets, and unsupported protocols. Message content has no command-execution or arbitrary application-launch interface.

Attachments stay inert in the reader. Saving requires an explicit action and a destination chosen through NSSavePanel. Filenames are normalized, and the export contains the original attachment bytes. Cosmic Mail does not automatically execute, open, or unpack attachments, and it preserves the source message.

## Bounded file processing

Native Swift readers validate MIME structure, MSG/CFB storage chains, and mailbox records. Nesting, parse work, part counts, message sizes, index metadata, image dimensions, and attachment sizes have explicit limits. Compound-file readers check offsets and detect cyclic chains. [TECHNICAL.md](TECHNICAL.md) maintains the current budgets and supported format details.

Archive indexing is incremental and cancellable. Source-file identity checks detect changes during reading; presentation ownership keeps superseded selections from replacing current content. Parsing and search run away from the main UI so normal navigation stays responsive.

## Verification and reporting

Security checks cover passive HTML reconstruction, remote-resource blocking, malformed file structures, image validation, confirmed links, and attachment handling. Use small synthetic fixtures and the focused procedures in [QA.md](QA.md), and verify the sandbox signature for an app release. Retain reusable test code and concise findings, with private mail and full logs excluded from test artifacts and the repository.

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/sd800/cosmic-mail/security/advisories/new). Include the affected version and a minimal synthetic reproduction; keep private mail and credentials out of public issues.
