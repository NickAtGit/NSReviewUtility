// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NSReviewUtility",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "NSReviewUtility", targets: ["NSReviewUtility"])],
    targets: [
        .target(name: "NSReviewUtility"),
        .testTarget(name: "NSReviewUtilityTests", dependencies: ["NSReviewUtility"]),
    ]
)
