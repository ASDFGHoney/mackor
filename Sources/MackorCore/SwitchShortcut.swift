import Foundation

/// macOS의 "이전 입력 소스 선택" 단축키. mackor는 시스템 설정을 바꾸지 않고
/// 사용자가 이미 쓰고 있는 이 단축키(기본 ⌃Space)를 그대로 합성해서 전환한다.
public struct SwitchShortcut: Equatable, Sendable {
    /// 가상 키코드(Space = 49).
    public var keyCode: UInt16
    /// CGEventFlags 원시값(⇧ 0x20000, ⌃ 0x40000, ⌥ 0x80000, ⌘ 0x100000, fn 0x800000).
    public var modifierFlags: UInt64

    public init(keyCode: UInt16, modifierFlags: UInt64) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public static let controlSpace = SwitchShortcut(keyCode: 49, modifierFlags: Modifier.control.flag)

    public enum Modifier: CaseIterable, Sendable {
        case control, option, shift, command

        public var flag: UInt64 {
            switch self {
            case .shift: 0x20000
            case .control: 0x40000
            case .option: 0x80000
            case .command: 0x100000
            }
        }

        /// 왼쪽 수정키의 가상 키코드.
        public var keyCode: UInt16 {
            switch self {
            case .shift: 56
            case .control: 59
            case .option: 58
            case .command: 55
            }
        }
    }

    /// 누를 순서대로의 수정키.
    public var modifiers: [Modifier] {
        Modifier.allCases.filter { modifierFlags & $0.flag != 0 }
    }

    /// 기능키 단축키에 macOS가 함께 저장하는 fn 플래그(NSEvent.ModifierFlags.function, CGEventFlags.maskSecondaryFn).
    /// 누를 키가 아니라 표시라서, 하드웨어 기능키처럼 단축키 키 이벤트에만 붙인다.
    public var keyFlags: UInt64 { modifierFlags & 0x800000 }

    /// com.apple.symbolichotkeys 의 AppleSymbolicHotKeys에서 전환 단축키를 고른다.
    /// 60(이전 입력 소스)을 우선하고, 꺼져 있으면 61(다음 입력 소스)을 쓴다. 둘 다 꺼져 있으면 nil.
    /// 사용자가 한 번도 바꾸지 않아 항목이 없으면 macOS 기본값(⌃Space, 켜짐)이다.
    public static func resolve(symbolicHotKeys: [String: Any]?) -> SwitchShortcut? {
        guard let entry = symbolicHotKeys?["60"] else { return .controlSpace }
        if let shortcut = SwitchShortcut(entry: entry) { return shortcut }
        return symbolicHotKeys?["61"].flatMap(SwitchShortcut.init(entry:))
    }

    /// 켜져 있는 항목만 해석한다. parameters = [문자 코드, 키코드, 수정키 플래그].
    init?(entry: Any) {
        guard let entry = entry as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
              let keyCode = UInt16(exactly: parameters[1].intValue) else { return nil }
        self.init(keyCode: keyCode, modifierFlags: parameters[2].uint64Value)
    }
}
