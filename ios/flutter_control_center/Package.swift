// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_control_center",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-control-center", targets: ["flutter_control_center"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_control_center",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
