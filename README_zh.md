# <img src="docs/assets/cosmic-mail.png" width="96" align="right" alt=""> Cosmic Mail<br clear="right">

[English](README.md)

Cosmic Mail 是一款原生 macOS 应用，用于阅读已保存的邮件，以及接住误触的邮件链接。

在简洁、熟悉的 Mac 界面中打开邮件或浏览存档。支持深浅色阅读、邮件详情和附件另存为。将 Cosmic Mail 设为邮件链接的默认应用后，`mailto:` 链接会以可阅读、可复制的信息展示，无需登录邮箱。

## 产品理念

Cosmic Mail 的设计源于一个简单的想法：**打开一条链接或一个文件，不应该意味着必须进入一整套操作流程。** 在 macOS 上，有两件日常小事却常常比想象中麻烦：点击电子邮件链接，以及查看本地保存的邮件存档。

**点击邮件链接，并不意味着用户想要撰写邮件。** 网页中的 `mailto:` 链接看起来可能与普通超链接没有区别，但在默认设置下，只需点击一次，就会启动 Apple Mail 并弹出邮件撰写窗口。对于 iCloud+ 用户，这类无意间触发的操作还可能导致未使用的「隐藏邮件地址」别名不断积累，之后不得不手动清理。Cosmic Mail 提供了一种更符合用户实际意图的处理方式。将其设为默认邮件应用后，用户可以直接查看或复制链接中的收件人、主题和正文，无需打开邮件撰写窗口，也不会因此生成新的邮件别名。

**查看邮件存档，本应像打开普通文件一样简单。** Apple Mail 要求用户先将 MBOX 存档导入邮件资料库，才能浏览其中的内容。对于只是想查看 Gmail 备份或翻阅历史邮件的用户来说，这无疑增加了不必要的步骤。Cosmic Mail 可以直接打开邮件文件及所支持的邮件存档，无需配置邮箱账户，也不必导入资料库，同时不会修改原始文件。

**Cosmic Mail 是一款邮件阅读工具，而不是另一个收件箱。** 它有意将功能聚焦于本地邮件阅读和邮件链接处理，将账户管理、邮件同步和发送交给用户原本使用的邮件服务。它的目标不是增加一套新的邮件操作流程，而是让用户不再被迫进入那些原本就无意开启的流程。

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

邮件留在你的 Mac 上。直接读取你打开的文件，不建立导入资料库，不上传云端。阻止远程图片和其他远程内容，不运行邮件脚本或嵌入对象，不自动打开附件；邮件内的链接仅提供复制，不直接打开网页或其他应用。应用仅保存阅读偏好，不跨启动保存邮件内容。

## 网站

产品网站：[cmail.songming.org](https://cmail.songming.org/)。静态网站源码位于 [web/](web/README.md)，双击 `web/index.html` 即可本地打开，通过 GitHub Actions 发布。

## 开发

需要 **Xcode 16 或更新版本**、macOS SDK、Swift 和 Python 3，无第三方软件包依赖。

```sh
./scripts/test.sh
./scripts/build.sh
```

安装包输出至 `dist/`。详见[技术文档](docs/TECHNICAL.md)和[安全设计](docs/SECURITY.md)。

## 许可证

Cosmic Mail 采用 [MIT 许可证](LICENSE)。
