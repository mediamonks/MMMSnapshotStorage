// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "MMMSnapshotStorage",
    platforms: [
        .iOS(.v11)
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
		.package(url: "https://github.com/mediamonks/MMMLoadable", .upToNextMajor(from: "1.5.0"))
    ],
    targets: [
        .target(
            name: "MMMSnapshotStorage",
            dependencies: [
				"MMMPromisingResult",
				"MMMLog",
				"MMMCommonCore"
            ]
		),
		.target(
			name: "MMMPromisingResult",
			dependencies: []
		),
		.target(
			name: "MMMStoredLoadable",
			dependencies: [
				"MMMLog",
				"MMMCommonCore",
				"MMMSnapshotStorage",
				"MMMLoadable"
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
