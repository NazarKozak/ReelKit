// swift-tools-version: 6.0
//
//  Package.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//

import PackageDescription

let package = Package(
    name: "SurfaceRecorderSDK",
    platforms: [
        .iOS(.v17),
        .macOS(.v12)
    ],
    products: [
        .library(name: "SurfaceRecorderSDK", targets: ["SurfaceRecorderSDK"])
    ],
    targets: [
        .target(
            name: "SurfaceRecorderSDK",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SurfaceRecorderSDKTests",
            dependencies: ["SurfaceRecorderSDK"]
        )
    ]
)
