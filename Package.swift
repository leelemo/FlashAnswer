// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlashAnswer",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2")
    ],
    targets: [
        .target(
            name: "FlashAnswer",
            dependencies: ["CoreXLSX"],
            path: "FlashAnswer"
        )
    ]
)
