// swift-tools-version:5.10
import PackageDescription

let vipsInclude = "Vendor/libvips/include"
let vipsLib = "Vendor/libvips/lib"

let package = Package(
    name: "Photokompressor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "photokompressor-cli", targets: ["PhotokompressorCLI"]),
        .library(name: "PhotokompressorCore", targets: ["PhotokompressorCore"]),
    ],
    targets: [
        .target(
            name: "CVips",
            path: "Sources/CVips",
            cSettings: [
                .unsafeFlags([
                    "-I\(vipsInclude)",
                    "-I\(vipsInclude)/glib-2.0",
                    "-I\(vipsInclude)/glib-2.0-config",
                ])
            ]
        ),
        .target(
            name: "PhotokompressorCore",
            dependencies: ["CVips"],
            path: "Sources/PhotokompressorCore",
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc", "-I\(vipsInclude)",
                    "-Xcc", "-I\(vipsInclude)/glib-2.0",
                    "-Xcc", "-I\(vipsInclude)/glib-2.0-config",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(vipsLib)",
                    "-lvips.42",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
                ])
            ]
        ),
        .executableTarget(
            name: "PhotokompressorCLI",
            dependencies: ["PhotokompressorCore"],
            path: "Sources/PhotokompressorCLI"
        ),
        .testTarget(
            name: "PhotokompressorCoreTests",
            dependencies: ["PhotokompressorCore"],
            path: "Tests/PhotokompressorCoreTests"
        ),
    ]
)
