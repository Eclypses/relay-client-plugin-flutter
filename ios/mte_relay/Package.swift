// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let remoteRelayPackageUrl = "https://github.com/Eclypses/mte-relay-client-ios.git"
let remoteRelayPackageVersion = "5.3.0"

func packageDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
}

func readLocalProperty(_ key: String) -> String? {
    let fileManager = FileManager.default
    let searchPaths = [
        packageDirectory().appendingPathComponent("local.properties"),
        packageDirectory().deletingLastPathComponent().appendingPathComponent("local.properties"),
        packageDirectory().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("local.properties")
    ]

    for path in searchPaths where fileManager.fileExists(atPath: path.path) {
        guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
            continue
        }

        for rawLine in contents.split(whereSeparator: \ .isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == key {
                let value = parts[1]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
    }

    return nil
}

let localRelayPackagePath = ProcessInfo.processInfo.environment["MTE_RELAY_IOS_PATH"]
    ?? readLocalProperty("mteRelayIosPath")

let relayPackageDependency: Package.Dependency
if let localRelayPackagePath, !localRelayPackagePath.isEmpty {
    relayPackageDependency = .package(path: localRelayPackagePath)
} else {
    // A pre-release is pinned exactly. SemVer ranges exclude pre-release versions, so
    // `from: "5.3.0-beta.1"` would not resolve later betas and reads as if it might;
    // `.exact` says what is meant. Switch back to `from:` at the first GA release.
    let version = Version(stringLiteral: remoteRelayPackageVersion)
    relayPackageDependency = version.prereleaseIdentifiers.isEmpty
        ? .package(url: remoteRelayPackageUrl, from: version)
        : .package(url: remoteRelayPackageUrl, exact: version)
}

let package = Package(
    name: "mte_relay",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "mte-relay",
                 targets: ["mte_relay"])
    ],
    dependencies: [
        relayPackageDependency
    ],
    targets: [
        .target(
            name: "mte_relay",
            dependencies: [
                .product(name: "Relay", package: "mte-relay-client-ios")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
