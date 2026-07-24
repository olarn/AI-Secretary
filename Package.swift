// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AISecretary",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AISecretaryApp", targets: ["AISecretaryApp"])
    ],
    targets: [
        .target(
            name: "AssistantState"
        ),
        .executableTarget(
            name: "AISecretaryApp",
            dependencies: ["AssistantState"]
        ),
        .testTarget(
            name: "AssistantStateTests",
            dependencies: ["AssistantState"]
        )
    ]
)
