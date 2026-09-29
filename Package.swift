// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mackor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mackor", targets: ["mackor"]),
    ],
    targets: [
        // 순수 로직: 전환 중 입력 보류, 전환 단축키 해석, 키 리매핑 계산, 설정 도우미 단계 전이. AppKit에 의존하지 않아 단위 테스트가 가능하다.
        .target(name: "MackorCore"),
        // 메뉴 막대 앱: 이벤트 탭, HID 리매핑, 권한·로그인 항목, 설정 도우미(SwiftUI).
        .executableTarget(
            name: "mackor",
            dependencies: ["MackorCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "MackorCoreTests", dependencies: ["MackorCore"]),
    ]
)
