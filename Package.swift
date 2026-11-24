// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HourRest",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HourRest", targets: ["HourRest"]),
    ],
    targets: [
        // 纯逻辑：整点计算、暂停、推迟合并、冷却等，不依赖 AppKit，便于单测。
        .target(name: "HourRestCore"),
        // 菜单栏应用本体（AppKit + SwiftUI）。
        .executableTarget(name: "HourRest", dependencies: ["HourRestCore"]),
        .testTarget(name: "HourRestCoreTests", dependencies: ["HourRestCore"]),
    ]
)
