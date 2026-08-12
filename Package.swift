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
            revision: "e9db556eb47958cd904366647b1a45c831cbc38f"
        ),
        .package(
            url: "https://github.com/mutle/swift-uwp",
            revision: "9506997bbc759b168cf45a2022a22a2b4294d7c7"
        ),
        .package(
            url: "https://github.com/mutle/swift-windowsfoundation",
            revision: "04ba0d2f81c2cf137147de485619fa5a5d3ab974"
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
