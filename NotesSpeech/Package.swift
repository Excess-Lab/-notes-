// swift-tools-version: 6.0
import PackageDescription

// Распознавание речи локально: GigaAM v3 через sherpa-onnx (Apache-2.0) и Whisper через WhisperKit (MIT).
// Отдельно от NotesCore: здесь тяжёлые зависимости, и тесты NotesCore не должны их собирать.
// Перед первой сборкой: ./Scripts/fetch-sherpa-onnx.sh (собирает Vendor/SherpaOnnx.xcframework).
let package = Package(
    name: "NotesSpeech",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NotesSpeech", targets: ["NotesSpeech"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        .binaryTarget(name: "SherpaOnnxC", path: "Vendor/SherpaOnnx.xcframework"),
        .target(
            name: "NotesSpeech",
            dependencies: ["SherpaOnnxC", .product(name: "WhisperKit", package: "WhisperKit")],
            // onnxruntime внутри sherpa-onnx написан на C++ и использует Accelerate и Core ML.
            linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"), .linkedFramework("CoreML")]
        ),
        .testTarget(name: "NotesSpeechTests", dependencies: ["NotesSpeech"]),
    ],
    swiftLanguageModes: [.v5]
)
