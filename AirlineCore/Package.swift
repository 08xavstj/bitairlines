// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirlineCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AirlineCore", targets: ["CoreSim", "CoreCatalog", "CoreWorld"])],
    targets: [
        .target(name: "CoreSim"),
        .target(name: "CoreCatalog", dependencies: ["CoreSim"]),
        .target(name: "CoreWorld", dependencies: ["CoreSim", "CoreCatalog"]),
        .testTarget(name: "CoreSimTests", dependencies: ["CoreSim"]),
        .testTarget(name: "CoreCatalogTests", dependencies: ["CoreCatalog", "CoreSim"]),
        .testTarget(name: "CoreWorldTests", dependencies: ["CoreWorld", "CoreCatalog", "CoreSim"]),
    ]
)
