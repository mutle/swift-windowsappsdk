// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "swift-windowsappsdk",
    products: [
        .library(name: "WinAppSDK", type: .dynamic, targets: ["WinAppSDK"]),
        .library(name: "CWinAppSDK", targets: ["CWinAppSDK"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/mutle/swift-cwinrt",
            revision: "a5988c9ec83d9ae1f1a4cd83051127f625ff60f7"
        ),
        .package(
            url: "https://github.com/mutle/swift-uwp",
            revision: "7aff869b2a6badeeaf82b9f68837f755995154e9"
        ),
        .package(
            url: "https://github.com/mutle/swift-windowsfoundation",
            revision: "a112318dc42f2031b18a7a2db5d03fc46f452449"
        ),
    ],
    targets: [
        .target(
            name: "WinAppSDK",
            dependencies: [
                .product(name: "CWinRT", package: "swift-cwinrt", condition: .when(platforms: [.windows])),
                .product(name: "UWP", package: "swift-uwp", condition: .when(platforms: [.windows])),
                .product(name: "WindowsFoundation", package: "swift-windowsfoundation", condition: .when(platforms: [.windows])),
                .target(name: "CWinAppSDK", condition: .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "CWinAppSDK",
            resources: [
                .copy("nuget/bin"),
            ]
        ),
        .testTarget(
            name: "WinAppSDKTests",
            dependencies: [
                "WinAppSDK",
                "CWinAppSDK",
            ]
        )
    ]
)
