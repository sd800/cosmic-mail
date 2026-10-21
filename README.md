# <img src="docs/assets/cosmic-mail.png" width="96" align="right" alt=""> Cosmic Mail<br clear="right">

[简体中文](README_zh.md)

Cosmic Mail is a native macOS app for reading saved email and catching email links before they turn into unwanted compose windows.

Open a message or browse an archive in a quiet, familiar Mac interface. Read in light or dark mode, inspect message details, and save individual attachments. When Cosmic Mail is your chosen email-link app, `mailto:` links open as readable, copyable details. No email account is needed.

## Install

Download the universal app ZIP from [Releases](https://github.com/sd800/cosmic-mail/releases), unzip it, and move **Cosmic Mail.app** to Applications. macOS 14 or later is required. Apple Silicon and Intel builds are included in the same app.

This release is ad-hoc signed and is not Apple notarized. For a GitHub download that macOS blocks, use **System Settings → Privacy & Security → Open Anyway** after checking the source. There is no need to disable Gatekeeper.

## Open mail

Use **Open**, press **⌘O**, or drop files into the window. Finder's **Open With → Cosmic Mail** works too. To make it the default for an email file type, use Finder's **Get Info → Open with → Change All**.

Supported formats: `.eml/.mime/.emlx/.msg/.oft/.mbox/.mbx/.mbo`, Apple Mail mailbox folders, and Maildir folders. MBX files must use the MBOX format. Outlook PST/OST and Outlook for Mac OLM archives are not supported in this release; export them as EML/MBOX first. Encrypted messages require a decrypted export from their original email application.

## Catch email links

Open **Cosmic Mail → Settings** (**⌘,**) and choose **Use Cosmic Mail for email links**. This is a separate choice from file associations. Installation does not change either default automatically.

Recipients, Cc/Bcc, subject, and message text appear in a normal window with copy controls. Cosmic Mail does not compose or send mail.

## Privacy and safety

Your mail stays on your Mac. Messages are read from the files you open, without an imported library or cloud upload. Remote images and other remote content are blocked. Email scripts and embedded objects do not run, attachments never open automatically, and website links require confirmation. Only reading preferences are saved between launches.

## Development

Build with **Xcode 16 or later**, an installed macOS SDK, Swift, and Python 3. No external packages are required.

```sh
./scripts/test.sh
./scripts/build.sh
```

The release ZIP is written to `dist/`. See [technical documentation](docs/TECHNICAL.md) and [security design](docs/SECURITY.md).

© 2026 Songming.org
