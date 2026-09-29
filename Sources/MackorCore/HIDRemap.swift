import Foundation

public enum ToggleKeyCode {
    /// kVK_F18. Caps Lock이 HID 단계에서 리매핑되어 들어오는 키. 이 키만 한/영 전환 키로 본다.
    public static let f18: UInt16 = 79
}

/// 한/영 키는 Caps Lock 하나다. HID 단계에서 F18로 바꿔, 대문자 고정 상태를 건드리지 않는 평범한 키로 들어오게 한다.
public enum HIDRemap {
    public static let sourceKey = "HIDKeyboardModifierMappingSrc"
    public static let destinationKey = "HIDKeyboardModifierMappingDst"
    /// Caps Lock (page 7 키보드 << 32 | usage 0x39).
    public static let capsLock: UInt64 = 0x7_0000_0039
    /// F18 (usage 0x6D).
    public static let target: UInt64 = 0x7_0000_006D
    /// 0.2.0까지 한/영 키로 고를 수 있던 오른쪽 Command·Option·Control. 이 키 → F18 항목은 우리 것으로 보고 지운다.
    static let legacySources: Set<UInt64> = [0x7_0000_00E7, 0x7_0000_00E6, 0x7_0000_00E4]

    public struct Entry: Equatable, Hashable, Sendable {
        public var source: UInt64
        public var destination: UInt64

        public init(source: UInt64, destination: UInt64) {
            self.source = source
            self.destination = destination
        }

        public init?(dictionary: [String: Any]) {
            guard let source = (dictionary[HIDRemap.sourceKey] as? NSNumber)?.uint64Value,
                  let destination = (dictionary[HIDRemap.destinationKey] as? NSNumber)?.uint64Value else { return nil }
            self.init(source: source, destination: destination)
        }

        public var dictionary: [String: NSNumber] {
            [HIDRemap.sourceKey: NSNumber(value: source), HIDRemap.destinationKey: NSNumber(value: destination)]
        }

        /// mackor가 넣은 항목인지. Caps Lock(과 이전 버전의 오른쪽 Command·Option·Control) → F18 조합만 우리 것으로 본다.
        var isOurs: Bool {
            destination == HIDRemap.target && (source == HIDRemap.capsLock || HIDRemap.legacySources.contains(source))
        }
    }

    public struct Plan: Equatable, Sendable {
        public var entries: [Entry]
        public var changed: Bool
        /// Caps Lock에 이미 다른 매핑이 있어 적용하지 않았을 때 그 항목. 그 키보드에서는 한/영 키가 동작하지 않는다.
        public var conflict: Entry?
        /// 이번에 Caps Lock → F18을 새로 넣는다. 그 뒤로는 켜진 Caps Lock을 끌 키가 없으므로 mackor가 끈다.
        public var addsCapsLock: Bool
    }

    /// 키보드 하나의 현재 매핑에서 mackor 항목만 바꾼 결과를 계산한다. active가 false면 mackor 항목을 지운다.
    /// 다른 앱이나 사용자가 넣은 항목은 순서까지 그대로 두고, 덮어쓰지 않는다. 이전 버전이 넣은 항목은 함께 정리한다.
    public static func plan(current: [Entry], active: Bool) -> Plan {
        let ours = Entry(source: capsLock, destination: target)
        var entries = current.filter { !$0.isOurs }
        var conflict: Entry?
        if active {
            if let existing = entries.first(where: { $0.source == capsLock }) {
                conflict = existing
            } else {
                entries.append(ours)
            }
        }
        return Plan(entries: entries, changed: Set(entries) != Set(current) || entries.count != current.count,
                    conflict: conflict, addsCapsLock: entries.contains(ours) && !current.contains(ours))
    }

    /// 시스템 설정 › 키보드 › 키보드 단축키 › 보조 키에서 Caps Lock을 다른 동작으로 바꿔 두었는지.
    /// 이 설정(HIDKeyboardModifierMappingPairs)은 UserKeyMapping보다 먼저 적용되어, 그 키보드에서는 우리 매핑이 가려진다.
    /// 항등(Caps Lock → Caps Lock)은 바꾸지 않은 것과 같다. 다른 키 → Caps Lock은 그 키가 한/영 키가 될 뿐이다.
    public static func isCapsLockRemapped(modifierPairs: [Entry]) -> Bool {
        modifierPairs.contains { $0.source == capsLock && $0.destination != capsLock }
    }
}
