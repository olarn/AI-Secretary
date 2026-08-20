// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AISecretary",
    platforms: [
        // 26, not 14, since Sprint 21: the Liquid Glass APIs (`glassEffect`,
        // `.buttonStyle(.glass)`) exist only from macOS 26, and the owner chose
        // dropping 14/15 over maintaining every surface in two shapes behind
        // `if #available`. The app has not shipped, so the cost was near zero.
        // The string form: tools 5.9 predates a `.v26` case, and bumping the
        // tools version would drag the language mode along with it.
        .macOS("26.0")
    ],
    products: [
        .executable(name: "AISecretaryApp", targets: ["AISecretaryApp"])
    ],
    dependencies: [
        // Typed functional programming: Option instead of nil, Either instead of
        // throws, plus |> >>> and curry for point-free composition.
        .package(url: "https://github.com/bow-swift/bow.git", from: "0.8.0")
    ],
    targets: [
        // Bow plus the Sendable conformances it predates. Domain targets depend
        // on this, never on Bow directly, so those are declared exactly once.
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
