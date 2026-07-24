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
        .target(
            name: "ProjectRegistry"
        ),
        .target(
            name: "Permissions",
            dependencies: ["ProjectRegistry"]
        ),
        .target(
            name: "ToolAdapters",
            dependencies: ["ProjectRegistry", "Permissions"]
        ),
        .target(
            name: "LLMProvider"
        ),
        .target(
            name: "Credentials"
        ),
        .target(
            name: "SecretaryCore",
            dependencies: ["AssistantState", "ProjectRegistry", "Permissions", "ToolAdapters", "LLMProvider"]
        ),
        .executableTarget(
            name: "AISecretaryApp",
            dependencies: [
                "AssistantState", "SecretaryCore", "ProjectRegistry",
                "Permissions", "ToolAdapters", "LLMProvider", "Credentials"
            ]
        ),
        .testTarget(
            name: "AssistantStateTests",
            dependencies: ["AssistantState"]
        ),
        .testTarget(
            name: "ProjectRegistryTests",
            dependencies: ["ProjectRegistry"]
        ),
        .testTarget(
            name: "PermissionsTests",
            dependencies: ["Permissions", "ProjectRegistry"]
        ),
        .testTarget(
            name: "ToolAdaptersTests",
            dependencies: ["ToolAdapters", "ProjectRegistry", "Permissions"]
        ),
        .testTarget(
            name: "LLMProviderTests",
            dependencies: ["LLMProvider"]
        ),
        .testTarget(
            name: "CredentialsTests",
            dependencies: ["Credentials"]
        ),
        .testTarget(
            name: "SecretaryCoreTests",
            dependencies: ["SecretaryCore", "AssistantState", "ProjectRegistry", "Permissions", "ToolAdapters", "LLMProvider"]
        )
    ]
)
