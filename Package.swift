// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DICOMTestTool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DICOMTestTool", targets: ["DICOMTestTool"]),
        .executable(name: "dicomcli", targets: ["dicomcli"]),
        .library(name: "DicomCore", targets: ["DicomCore"]),
    ],
    targets: [
        .target(name: "DicomCore"),
        .executableTarget(name: "DICOMTestTool", dependencies: ["DicomCore"]),
        .executableTarget(name: "dicomcli", dependencies: ["DicomCore"]),
    ]
)
