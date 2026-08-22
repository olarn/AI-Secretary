// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AISecretary",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "AISecretaryApp", targets: ["AISecretaryApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/bow-swift/bow.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "FunctionalCore",
            dependencies: [.product(name: "Bow", package: "bow")]
        ),
        .target(
            name: "AssistantState",
            dependencies: ["FunctionalCore"]
        ),
        .target(
            name: "ProjectRegistry",
            dependencies: ["FunctionalCore"]
        ),
        .target(
            name: "Permissions",
            dependencies: ["ProjectRegistry", "FunctionalCore"]
        ),
        .target(
            name: "ToolAdapters",
            dependencies: ["ProjectRegistry", "Permissions", "FunctionalCore"]
        ),
        .target(
            name: "LLMProvider",
            dependencies: ["FunctionalCore"]
        ),
        .target(
            name: "SecretaryCore",
            dependencies: ["FunctionalCore", "AssistantState", "ProjectRegistry", "Permissions", "ToolAdapters", "LLMProvider"]
        ),
        .executableTarget(
            name: "AISecretaryApp",
            dependencies: [
                "FunctionalCore", "AssistantState", "SecretaryCore", "ProjectRegistry",
                "Permissions", "ToolAdapters", "LLMProvider"
            ]
        ),
        .testTarget(
            name: "AssistantStateTests",
            dependencies: ["AssistantState", "FunctionalCore"]
        ),
        .testTarget(
            name: "ProjectRegistryTests",
            dependencies: ["ProjectRegistry", "FunctionalCore"]
        ),
        .testTarget(
            name: "PermissionsTests",
            dependencies: ["Permissions", "ProjectRegistry", "FunctionalCore"]
        ),
        .testTarget(
            name: "ToolAdaptersTests",
            dependencies: ["ToolAdapters", "ProjectRegistry", "Permissions", "FunctionalCore"]
        ),
        .testTarget(
            name: "LLMProviderTests",
            dependencies: ["LLMProvider", "FunctionalCore"]
        ),
        .testTarget(
            name: "SecretaryCoreTests",
            dependencies: ["SecretaryCore", "FunctionalCore", "AssistantState", "ProjectRegistry", "Permissions", "ToolAdapters", "LLMProvider"]
        )
    ]
)
