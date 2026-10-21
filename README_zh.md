# <img src="docs/assets/cosmic-mail.png" width="96" align="right" alt=""> Cosmic Mail<br clear="right">

[English](README.md)

Cosmic Mail 是一款原生 macOS 应用，用于阅读已保存的邮件，以及接住误触的邮件链接。

在简洁、熟悉的 Mac 界面中打开邮件或浏览存档。支持深浅色阅读、邮件详情和附件另存为。将 Cosmic Mail 设为邮件链接的默认应用后，`mailto:` 链接会以可阅读、可复制的信息展示，无需登录邮箱。

## 安装

从 [Releases](https://github.com/sd800/cosmic-mail/releases) 下载通用版应用 ZIP，解压后将 **Cosmic Mail.app** 移入应用程序文件夹。需要 macOS 14 或更新版本；同一个应用包含 Apple Silicon 和 Intel 版本。

此版本使用临时代码签名，尚未经过 Apple 公证。如果从 GitHub 下载后被 macOS 阻止，请确认来源后，在**系统设置 → 隐私与安全性**中选择**仍要打开**，无需关闭 Gatekeeper。

## 打开邮件

点击“打开”、按 **⌘O**，或将文件拖入窗口。也可在 Finder 中选择**打开方式 → Cosmic Mail**。若需将某种邮件文件默认交由本应用打开，可通过 Finder 的**显示简介 → 打开方式 → 全部更改**设置。

支持格式：`.eml/.mime/.emlx/.msg/.oft/.mbox/.mbx/.mbo`、Apple Mail 邮箱文件夹和 Maildir 文件夹。MBX 文件须使用 MBOX 格式。此版本不支持 Outlook PST/OST/OLM 存档，可先从原应用导出 EML/MBOX。加密邮件需要由原邮件应用解密导出后阅读。

## 接住邮件链接

通过 **Cosmic Mail → 设置**（**⌘,**），选择**使用 Cosmic Mail 打开邮件链接**。这与文件类型关联分别设置，安装不会自动更改这两类默认选项。

收件人、抄送、密送、主题和正文会在普通窗口中展示，并提供复制按钮。本应用不撰写或发送邮件。

## 隐私与安全

邮件留在你的 Mac 上。直接读取你打开的文件，不建立导入资料库，不上传云端。阻止远程图片和其他远程内容，不运行邮件脚本或嵌入对象，不自动打开附件；网页链接须经确认。应用仅保存阅读偏好，不跨启动保存邮件内容。

## 开发

需要 **Xcode 16 或更新版本**、macOS SDK、Swift 和 Python 3，无第三方软件包依赖。

```sh
./scripts/test.sh
./scripts/build.sh
```

安装包输出至 `dist/`。详见[技术文档](docs/TECHNICAL.md)和[安全设计](docs/SECURITY.md)。

© 2026 Songming.org
