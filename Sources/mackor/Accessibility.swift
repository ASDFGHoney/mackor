import AppKit
import ApplicationServices
import Security

/// 접근성 권한. 이벤트 탭으로 한/영 키를 가로채는 데 필요하다.
enum Accessibility {
    /// 디버그(`--simulate-untrusted`): 실제 권한 대신 이 값을 쓴다. `kill -USR1 <pid>`로 허용·해제를 뒤집는다.
    /// 터미널에서 띄운 디버그 빌드는 터미널의 권한을 물려받아 항상 허용됨으로 보이기 때문이다.
    static var simulated: Bool? = CommandLine.arguments.contains("--simulate-untrusted") ? false : nil

    static var isTrusted: Bool { simulated ?? AXIsProcessTrusted() }

    /// 시스템 대화상자로 요청해 손쉬운 사용 목록에 mackor를 올리고, 시스템 설정의 그 화면을 연다.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings()
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// 이 앱의 코드 서명 요구 사항(designated requirement). 접근성 권한 항목은 이것에 묶이므로,
    /// 예전에 허용되었을 때와 다르면 목록의 항목이 낡았다고 짐작할 수 있다.
    static let designatedRequirement: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()
}
