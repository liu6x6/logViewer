// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LogViewerCustomMode",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LogViewerCustomMode",
            targets: ["LogViewerCustomMode"]
        )
    ],
    targets: [
        .target(
            name: "LogViewerCustomMode"
        )
    ]
)
