// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "VoiceStudio", platforms: [.macOS(.v13)], products: [.executable(name: "voice-studio", targets: ["VoiceStudio"])], targets: [.executableTarget(name: "VoiceStudio", resources: [.copy("index.html")])])
