// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SudokuEngine",
    products: [
        .library(name: "SudokuEngine", targets: ["SudokuEngine"]),
    ],
    targets: [
        .target(name: "SudokuEngine"),
        .testTarget(name: "SudokuEngineTests", dependencies: ["SudokuEngine"]),
    ]
)
