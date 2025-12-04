// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Grimoire",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Grimoire",
            targets: ["Grimoire"]),
        .executable(
            name: "GrimoireApp",
            targets: ["GrimoireApp"]),
    ],
    dependencies: [
        // Markdown rendering for preview
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.2.0")
    ],
    targets: [
        // Main library target containing shared code
        .target(
            name: "Grimoire",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: ".",
            exclude: [
                "Grimoire.xcodeproj",
                "Grimoire.app",
                ".build",
                "build.sh",
                "build_app.sh",
                "build_simple.sh",
                "create_xcode_project.sh",
                "setup_xcode.sh",
                "XCODE_GUIDE.md",
                "XCODE_SETUP.md",
                "Package.swift",  // Exclude this file itself
            ],
            sources: [
                "GrimoireApp.swift",
                "ContentView.swift",
                "SidebarView.swift",
                "EditorView.swift",
                "BacklinksView.swift",
                "SettingsView.swift",
                "NoteManager.swift",
                "SearchManager.swift",
                "Views",
                "FileManager",
                "Networking",
                "Resources",
            ]
        ),

        // App executable target
        .executableTarget(
            name: "GrimoireApp",
            dependencies: ["Grimoire"],
            path: ".",
            sources: ["GrimoireApp.swift"]
        ),

        // Test target
        .testTarget(
            name: "GrimoireTests",
            dependencies: ["Grimoire"],
            path: "../tests/macos-app/GrimoireTests"
        ),
    ]
)
