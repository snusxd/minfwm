// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MinfwmApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Minfwm", targets: ["MinfwmApp"])
    ],
    targets: [
        .executableTarget(
            name: "MinfwmApp",
            path: "Sources/MinfwmApp"
        )
    ]
)
