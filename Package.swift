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
		)
    ],
    dependencies: [
		.package(url: "https://github.com/mediamonks/MMMLog", .upToNextMajor(from: "1.2.1")),
		.package(url: "https://github.com/mediamonks/MMMCommonCore", .upToNextMajor(from: "1.2.1"))
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
        .testTarget(
            name: "MMMSnapshotStorageTests",
            dependencies: ["MMMSnapshotStorage"],
            path: "Tests"
		)
    ]
)
