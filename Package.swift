// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NowPlayingKit",
	platforms: [
		.iOS(.v17),
		.macOS(.v14),
	],
    products: [
        .library(
            name: "NowPlayingKit",
            targets: ["NowPlayingKit"]),
    ],
    targets: [
        .target(
            name: "NowPlayingKit"),
        .testTarget(
            name: "NowPlayingKitTests",
            dependencies: ["NowPlayingKit"]
        ),
    ]
)
