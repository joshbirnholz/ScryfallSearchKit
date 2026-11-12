// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ScryfallSearchKit",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "ScryfallSearchKit", targets: ["ScryfallSearchKit"]),
  ],
  targets: [
    .target(name: "ScryfallSearchKit"),
    .testTarget(
      name: "ScryfallSearchKitTests",
      dependencies: ["ScryfallSearchKit"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
