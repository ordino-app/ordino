// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ordino",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Geometry", targets: ["Geometry"]),
        .library(name: "LayoutEngine", targets: ["LayoutEngine"]),
        .library(name: "WindowKit", targets: ["WindowKit"]),
        .library(name: "ArrangeCore", targets: ["ArrangeCore"]),
        .executable(name: "ordino", targets: ["OrdinoApp"]),
        .executable(name: "ordino-probe", targets: ["ordino-probe"]),
    ],
    dependencies: [
        // Auto-update. Pinned exactly; bump deliberately (Dependabot opens PRs).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        // Pure value types. Foundation only.
        .target(name: "Geometry"),

        // Pure, deterministic layout math. Foundation only; no AppKit, no AX.
        .target(name: "LayoutEngine", dependencies: ["Geometry"]),

        // C shim exposing the private (but widely used) _AXUIElementGetWindow.
        .target(
            name: "AXPrivate",
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),

        // Accessibility + CoreGraphics window discovery and movement.
        .target(
            name: "WindowKit",
            dependencies: ["Geometry", "LayoutEngine", "AXPrivate"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        ),

        // Arrange / cycle / rotate / undo logic behind a backend protocol. Testable.
        .target(name: "ArrangeCore", dependencies: ["Geometry", "LayoutEngine"]),

        // The menu bar app.
        .executableTarget(
            name: "OrdinoApp",
            dependencies: [
                "Geometry", "LayoutEngine", "WindowKit", "ArrangeCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // Sparkle.framework is embedded in ordino.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        // Week-1 prototype CLI: discover windows, print a plan, optionally apply it.
        .executableTarget(
            name: "ordino-probe",
            dependencies: ["Geometry", "LayoutEngine", "WindowKit"]
        ),

        .testTarget(name: "GeometryTests", dependencies: ["Geometry"]),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine", "Geometry"]),
        .testTarget(name: "ArrangeCoreTests", dependencies: ["ArrangeCore", "LayoutEngine", "Geometry"]),
    ],
    swiftLanguageModes: [.v6]
)
