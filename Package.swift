// swift-tools-version:6.0
import PackageDescription

let package: Package = .init(
    name: "swift-https-relay",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "https-relay", targets: ["Relay"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/dollup", from: "1.0.1"),

        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.96.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl", from: "2.36.0"),
    ],
    targets: [
        .executableTarget(
            name: "Relay",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
    ]
)
for target: Target in package.targets {
    switch target.type {
    case .plugin: continue
    case .binary: continue
    default: break
    }
    {
        $0 = ($0 ?? []) + [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
        ]
    }(&target.swiftSettings)
}
