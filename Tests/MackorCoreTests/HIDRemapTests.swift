import Foundation
import Testing
@testable import MackorCore

private typealias Entry = HIDRemap.Entry
private let capsLock = HIDRemap.capsLock
private let ours = Entry(source: capsLock, destination: HIDRemap.target)
/// 0.2.0까지 한/영 키로 고를 수 있던 오른쪽 Command(기본), Option, Control.
private let rightCommand: UInt64 = 0x7_0000_00E7
private let rightOption: UInt64 = 0x7_0000_00E6
private let rightControl: UInt64 = 0x7_0000_00E4
private let escape: UInt64 = 0x7_0000_0029
private let leftControl: UInt64 = 0x7_0000_00E0

@Suite("HID 키 리매핑")
struct HIDRemapTests {
    @Test("빈 매핑에 Caps Lock → F18을 추가한다")
    func addToEmpty() {
        let plan = HIDRemap.plan(current: [], active: true)
        #expect(plan.changed && plan.conflict == nil && plan.addsCapsLock)
        #expect(plan.entries == [ours])
    }

    @Test("이미 적용돼 있으면 쓰지 않는다")
    func idempotent() {
        let current = [Entry(source: escape, destination: leftControl), ours]
        let plan = HIDRemap.plan(current: current, active: true)
        #expect(!plan.changed && !plan.addsCapsLock, "이미 매핑돼 있으면 Caps Lock 상태도 건드리지 않는다")
        #expect(!HIDRemap.plan(current: current.reversed(), active: true).changed, "순서만 다른 건 같은 매핑")
    }

    @Test("이전 버전의 오른쪽 Command 항목은 Caps Lock으로 바꾸고 다른 매핑은 보존한다")
    func upgradesLegacy() {
        let other = Entry(source: escape, destination: leftControl)
        let plan = HIDRemap.plan(current: [other, Entry(source: rightCommand, destination: HIDRemap.target)], active: true)
        #expect(plan.entries == [other, ours] && plan.changed && plan.addsCapsLock)
    }

    @Test("이전 버전이 넣은 오른쪽 Command·Option·Control → F18 항목은 끌 때도 지운다")
    func removesLegacy() {
        let other = Entry(source: escape, destination: leftControl)
        let legacy = [rightCommand, rightOption, rightControl].map { Entry(source: $0, destination: HIDRemap.target) }
        let plan = HIDRemap.plan(current: legacy + [other], active: false)
        #expect(plan.entries == [other] && plan.changed && !plan.addsCapsLock)
    }

    @Test("Caps Lock에 다른 매핑이 있으면 덮어쓰지 않고 충돌로 알린다")
    func conflict() {
        let userMapping = Entry(source: capsLock, destination: escape)
        let plan = HIDRemap.plan(current: [userMapping, Entry(source: rightCommand, destination: HIDRemap.target)], active: true)
        #expect(plan.conflict == userMapping)
        #expect(plan.entries == [userMapping], "이전 버전의 우리 항목은 정리한다")
        #expect(!plan.addsCapsLock, "충돌이면 Caps Lock을 끄지 않는다")
    }

    @Test("끄면 우리 항목만 지운다")
    func remove() {
        let other = Entry(source: escape, destination: leftControl)
        let plan = HIDRemap.plan(current: [ours, other], active: false)
        #expect(plan.entries == [other] && plan.changed)
        #expect(!HIDRemap.plan(current: [other], active: false).changed)
    }

    @Test("다른 앱이 F18로 보낸 키나 오른쪽 Command를 다른 키로 보낸 항목은 우리 것이 아니다")
    func foreignUntouched() {
        let foreign = [Entry(source: escape, destination: HIDRemap.target), Entry(source: rightCommand, destination: escape)]
        let plan = HIDRemap.plan(current: foreign, active: false)
        #expect(plan.entries == foreign && !plan.changed)
    }

    @Test("IOKit 딕셔너리와 왕복 변환")
    func dictionaryRoundTrip() {
        #expect(Entry(dictionary: ours.dictionary) == ours)
        #expect(Entry(dictionary: ["HIDKeyboardModifierMappingSrc": NSNumber(value: 1)]) == nil)
    }

    @Test("보조 키에서 Caps Lock을 다른 동작으로 바꿨으면 우리 매핑이 가려진 것으로 본다")
    func modifierKeyRemapped() {
        #expect(HIDRemap.isCapsLockRemapped(modifierPairs: [Entry(source: capsLock, destination: escape)]))
        let swapped = [Entry(source: leftControl, destination: capsLock), Entry(source: capsLock, destination: leftControl)]
        #expect(HIDRemap.isCapsLockRemapped(modifierPairs: swapped), "Caps Lock과 Control을 맞바꾼 경우")
    }

    @Test("보조 키 설정이 없거나 Caps Lock을 그대로 두었으면 가리지 않는다")
    func modifierKeyUntouched() {
        #expect(!HIDRemap.isCapsLockRemapped(modifierPairs: []))
        // 실제 맥의 레지스트리 미러에서 흔히 보이는 항등 쌍과 같은 모양.
        let identity: [String: Any] = [HIDRemap.sourceKey: NSNumber(value: capsLock), HIDRemap.destinationKey: NSNumber(value: capsLock)]
        #expect(!HIDRemap.isCapsLockRemapped(modifierPairs: [identity].compactMap(Entry.init(dictionary:))), "항등은 바꾸지 않은 것과 같다")
        #expect(!HIDRemap.isCapsLockRemapped(modifierPairs: [Entry(source: leftControl, destination: capsLock)]),
                "다른 키 → Caps Lock은 그 키가 한/영 키가 될 뿐이다")
    }
}
