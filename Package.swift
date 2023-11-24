// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "NSReviewUtility",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [.library(name: "NSReviewUtility", targets: ["NSReviewUtility"])],
    targets: [.target(name: "NSReviewUtility")]
)
