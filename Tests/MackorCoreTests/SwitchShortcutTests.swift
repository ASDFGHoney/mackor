import Foundation
import Testing
@testable import MackorCore

private func entry(enabled: Bool, _ parameters: [Int]) -> [String: Any] {
    ["enabled": NSNumber(value: enabled),
     "value": ["type": "standard", "parameters": parameters.map { NSNumber(value: $0) }] as [String: Any]]
}

@Suite("전환 단축키 해석")
struct SwitchShortcutTests {
    @Test("설정한 적 없으면 macOS 기본값 ⌃Space")
    func defaultWhenMissing() {
        #expect(SwitchShortcut.resolve(symbolicHotKeys: nil) == .controlSpace)
        #expect(SwitchShortcut.resolve(symbolicHotKeys: ["32": entry(enabled: true, [0, 0, 0])]) == .controlSpace)
    }

    @Test("macOS가 저장하는 실제 형식(⌃Space)")
    func controlSpace() {
        let keys = ["60": entry(enabled: true, [32, 49, 262144]), "61": entry(enabled: true, [32, 49, 786432])]
        let shortcut = SwitchShortcut.resolve(symbolicHotKeys: keys)
        #expect(shortcut == .controlSpace)
        #expect(shortcut?.modifiers == [.control])
    }

    @Test("사용자가 바꾼 단축키를 그대로 쓴다")
    func customShortcut() {
        let keys = ["60": entry(enabled: true, [65535, 49, 0x100000 | 0x40000])]
        let shortcut = SwitchShortcut.resolve(symbolicHotKeys: keys)
        #expect(shortcut?.keyCode == 49 && shortcut?.modifiers == [.control, .command])
    }

    @Test("기능키(F18) 단축키의 fn 표시는 누를 수정키가 아니라 키 이벤트 플래그로 쓴다")
    func functionKeyShortcut() {
        let keys = ["60": entry(enabled: true, [65535, 79, 8388608])]
        let shortcut = SwitchShortcut.resolve(symbolicHotKeys: keys)
        #expect(shortcut?.keyCode == 79 && shortcut?.modifiers == [], "fn은 누를 수정키가 아니다")
        #expect(shortcut?.keyFlags == 0x800000)
        #expect(SwitchShortcut.controlSpace.keyFlags == 0)
    }

    @Test("이전 입력 소스가 꺼져 있으면 다음 입력 소스를 쓴다")
    func fallbackToNext() {
        let keys = ["60": entry(enabled: false, [32, 49, 262144]), "61": entry(enabled: true, [32, 49, 786432])]
        #expect(SwitchShortcut.resolve(symbolicHotKeys: keys)?.modifiers == [.control, .option])
    }

    @Test("둘 다 꺼져 있으면 전환할 수 없다")
    func bothDisabled() {
        let keys = ["60": entry(enabled: false, [32, 49, 262144]), "61": entry(enabled: false, [32, 49, 786432])]
        #expect(SwitchShortcut.resolve(symbolicHotKeys: keys) == nil)
    }
}
