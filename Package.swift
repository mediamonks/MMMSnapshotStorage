// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "MMMSnapshotStorage",
    platforms: [
        .iOS(.v11),
        .watchOS(.v5),
		.macOS(.v10_12),
		.tvOS(.v10)
    ],
    products: [
        .library(
            name: "MMMSnapshotStorage",
            targets: ["MMMSnapshotStorage"]
		),
		.library(
            name: "MMMStoredLoadable",
            targets: ["MMMStoredLoadable"]
		)
    ],
    dependencies: [
		.package(url: "https://github.com/mediamonks/MMMLog", .upToNextMajor(from: "1.2.1")),
		.package(url: "https://github.com/mediamonks/MMMCommonCore", .upToNextMajor(from: "1.2.1")),
		.package(url: "https://github.com/mediamonks/MMMLoadable", .upToNextMajor(from: "1.5.0")),
		.package(url: "https://github.com/mediamonks/MMMPromisingResult", .upToNextMajor(from: "0.1.0"))
    ],
    targets: [
        .target(
            name: "MMMSnapshotStorage",
            dependencies: [
				"MMMLog",
				"MMMCommonCore",
				"MMMPromisingResult"
            ]
		),
		.target(
			name: "MMMStoredLoadable",
			dependencies: [
				"MMMLog",
				"MMMCommonCore",
				"MMMSnapshotStorage",
				"MMMLoadable",
				"MMMPromisingResult"
			]
		),
        .testTarget(
            name: "MMMSnapshotStorageTests",
            dependencies: [
				"MMMSnapshotStorage",
				"MMMStoredLoadable"
			],
            path: "Tests"
		)
    ]
)
