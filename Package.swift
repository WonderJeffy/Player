// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Player",
    platforms: [
      .iOS(.v16)
    ],
    products: [
      .library(name: "Player", targets: ["Player"])
    ],
    targets: [
      .target(
          name: "Player",
          path: "Sources"
      )
    ],
    swiftLanguageModes: [.v6]
)
