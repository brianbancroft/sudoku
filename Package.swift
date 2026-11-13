// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SudokuEngine",
    products: [
        .library(name: "SudokuEngine", targets: ["SudokuEngine"]),
        .executable(name: "SudokuServer", targets: ["SudokuServer"]),
    ],
    targets: [
        .target(name: "SudokuEngine"),
        .target(
            name: "SudokuServerCore",
            dependencies: ["SudokuEngine"],
            path: "Server/Sources/SudokuServerCore"
        ),
        .executableTarget(
            name: "SudokuServer",
            dependencies: ["SudokuServerCore"],
            path: "Server/Sources/SudokuServer"
        ),
        .testTarget(name: "SudokuEngineTests", dependencies: ["SudokuEngine"]),
        .testTarget(
            name: "SudokuServerTests",
            dependencies: ["SudokuServerCore"],
            path: "Server/Tests/SudokuServerTests"
        ),
    ]
)
