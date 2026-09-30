import AppKit
import Carbon
import IOKit

/// 보안 입력(Secure Event Input). 켜져 있는 동안 macOS는 어느 앱이 켰든, 그 앱이 뒤에 있어도 모든 이벤트 탭에서 키 누름·뗌을 숨긴다
/// (수정키 변화만 보인다). 그래서 Caps Lock → F18이 mackor에 오지 않아 아무 일도 하지 않는다.
/// 비밀번호 칸이나 터미널의 보안 키보드 입력이 켜고, 뒤로 간 앱이 끄지 않은 채 남겨 두기도 한다.
enum SecureInput {
    /// 호출 한 번에 수 µs라 짧은 간격으로 확인해도 된다. 알림은 없다.
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// 보안 입력을 켠 앱 이름(진단·메뉴용). IO 레지스트리 루트의 IOConsoleUsers에서 이 사용자 세션의 kCGSSessionSecureInputPID로 찾는다
    /// (`ioreg -l | grep SecureInput`과 같은 값). 문서에 없는 키라 없으면 nil이다.
    /// CGSessionCopyCurrentDictionary의 같은 키는 보안 입력이 켜져 있으면 맨 앞 앱을 가리켜(macOS 27에서 확인) 쓰지 않는다.
    static var ownerName: String? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [[String: Any]],
              let session = users.first(where: { ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == getuid() }),
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
