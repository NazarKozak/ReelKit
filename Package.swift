// swift-tools-version: 6.0
//
//  Package.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//

import PackageDescription

let package = Package(
    name: "ReelKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v12)
    ],
    products: [
        .library(name: "ReelKit", targets: ["ReelKit"])
    ],
    targets: [
        .target(
            name: "ReelKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ReelKitTests",
            dependencies: ["ReelKit"]
        )
    ]
)
