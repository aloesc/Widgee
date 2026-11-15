// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgeeKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WidgeeCore", targets: ["WidgeeCore"]),
        .library(name: "Metrics", targets: ["Metrics"]),
        .library(name: "WidgetHost", targets: ["WidgetHost"]),
        .library(name: "Renderer", targets: ["Renderer"]),
        .library(name: "Background", targets: ["Background"]),
        .library(name: "AgentPrompt", targets: ["AgentPrompt"]),
        .library(name: "Layout", targets: ["Layout"]),
    ],
    targets: [
        .target(name: "WidgeeCore"),
        .target(name: "Metrics", dependencies: ["WidgeeCore"]),
        .target(name: "WidgetHost", dependencies: ["WidgeeCore", "Metrics"]),
        .target(name: "Background", dependencies: ["WidgeeCore"]),
        .target(name: "Renderer", dependencies: ["WidgeeCore", "Background"], exclude: ["COMPONENTS.md"]),
        .target(name: "AgentPrompt", dependencies: ["WidgeeCore"], resources: [.copy("Resources")]),
        .target(name: "Layout"),
        .testTarget(name: "LayoutTests", dependencies: ["Layout"]),
        .testTarget(name: "AgentPromptTests", dependencies: ["AgentPrompt", "WidgetHost", "WidgeeCore"]),
        .testTarget(name: "WidgeeCoreTests", dependencies: ["WidgeeCore"]),
        .testTarget(name: "MetricsTests", dependencies: ["Metrics"]),
        .testTarget(name: "WidgetHostTests", dependencies: ["WidgetHost"]),
        .testTarget(name: "RendererTests", dependencies: ["Renderer"]),
        .testTarget(name: "BackgroundTests", dependencies: ["Background"]),
    ]
)
