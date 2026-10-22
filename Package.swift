// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "CosmicMail", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "CosmicMail", targets: ["CosmicMail"])
  ],
  targets: [
    .target(name: "MailCore", linkerSettings: [.linkedLibrary("iconv")]),
    .executableTarget(name: "CosmicMail", dependencies: ["MailCore"]),
    .testTarget(name: "MailCoreTests", dependencies: ["MailCore"]),
    .testTarget(name: "CosmicMailTests", dependencies: ["CosmicMail", "MailCore"]),
  ])
