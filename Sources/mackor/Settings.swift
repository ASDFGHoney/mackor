import Foundation
import MackorCore

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// 처음 실행할 때 한 번만 로그인 항목에 등록한다. 이후 사용자가 끄면 그대로 둔다.
    var didOfferLoginItem: Bool {
        get { defaults.bool(forKey: "didOfferLoginItem") }
        set { defaults.set(newValue, forKey: "didOfferLoginItem") }
    }

    /// 설정을 마친 적이 있다(권한을 받았다). 이후 권한 없이 실행되면 소개 대신 권한 단계로 바로 안내한다.
    var didSetUp: Bool {
        get { defaults.bool(forKey: "didSetUp") }
        set { defaults.set(newValue, forKey: "didSetUp") }
    }

    /// 마지막으로 권한이 있었을 때의 코드 서명 요구 사항. 서명이 바뀌어 권한 항목이 낡았는지 짐작하는 데 쓴다.
    var lastTrustedRequirement: String? {
        get { defaults.string(forKey: "lastTrustedRequirement") }
        set { defaults.set(newValue, forKey: "lastTrustedRequirement") }
    }

    /// .app 번들로 실행 중인지. 터미널에서 띄운 개발용 실행 파일은 로그인 항목에 등록하면 안 된다
    /// (로그인할 때마다 macOS가 그 파일을 터미널로 연다).
    let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"

    /// 개발·검증용: 실제 키보드 매핑을 건드리지 않는다(`--no-remap`).
    let remapEnabled = !CommandLine.arguments.contains("--no-remap")

    /// 개발·검증용: 실행하자마자 설정 도우미를 띄운다(`--onboarding`, `--onboarding=permission|try|done`).
    let onboardingStart: OnboardingStep? = {
        guard let argument = CommandLine.arguments.first(where: { $0 == "--onboarding" || $0.hasPrefix("--onboarding=") }) else { return nil }
        switch argument.split(separator: "=").last {
        case "permission": return .permission
        case "try": return .tryIt
        case "done": return .done
        default: return .welcome
        }
    }()
}
