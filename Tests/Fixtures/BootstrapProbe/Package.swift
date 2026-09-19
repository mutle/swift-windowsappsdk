// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BootstrapProbe",
    dependencies: [
        .package(name: "swift-windowsappsdk", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "BootstrapProbe",
            dependencies: [
                .product(name: "WinAppSDK", package: "swift-windowsappsdk"),
            ]
        ),
    ]
)
