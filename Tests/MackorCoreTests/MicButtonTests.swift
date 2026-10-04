import Foundation
import Testing
@testable import MackorCore

private typealias Entry = HIDRemap.Entry
private let volumeUp = MicButtonRemap.volumeUp
private let volumeDown = MicButtonRemap.volumeDown
private let fn = MicButtonRemap.fn
private let ours = [Entry(source: volumeUp, destination: fn), Entry(source: volumeDown, destination: fn)]
/// Consumer 재생/일시정지.
private let playPause: UInt64 = 0xC_0000_00CD
private let mute: UInt64 = 0xC_0000_00E2

@Suite("DJI 마이크 버튼")
struct MicButtonTests {
    @Test("DJI Mic Mini 수신기만 알아본다")
    func receiver() {
        #expect(MicButtonRemap.isReceiver(vendorID: 0x2CA3, productID: 0x4011))
        #expect(!MicButtonRemap.isReceiver(vendorID: 0x2CA3, productID: 0x4012))
        #expect(!MicButtonRemap.isReceiver(vendorID: 0x05AC, productID: 0x4011))
        #expect(!MicButtonRemap.isReceiver(vendorID: nil, productID: nil))
    }

    @Test("빈 매핑에 볼륨 올림·내림 → Fn을 넣는다")
    func addToEmpty() {
        let plan = MicButtonRemap.plan(current: [], active: true)
        #expect(plan.changed && plan.entries == ours)
    }

    @Test("이미 적용돼 있으면 쓰지 않는다")
    func idempotent() {
        #expect(!MicButtonRemap.plan(current: ours, active: true).changed)
        #expect(!MicButtonRemap.plan(current: ours.reversed(), active: true).changed, "순서만 다른 건 같은 매핑")
    }

    @Test("한쪽만 있으면 나머지를 채운다")
    func fillsMissing() {
        let plan = MicButtonRemap.plan(current: [Entry(source: volumeUp, destination: fn)], active: true)
        #expect(plan.changed && Set(plan.entries) == Set(ours))
    }

    @Test("볼륨 키에 다른 매핑이 있으면 덮어쓰지 않는다")
    func keepsForeign() {
        let user = Entry(source: volumeUp, destination: playPause)
        let plan = MicButtonRemap.plan(current: [user], active: true)
        #expect(plan.entries == [user, Entry(source: volumeDown, destination: fn)])
    }

    @Test("끄면 우리 항목만 지운다")
    func remove() {
        let other = Entry(source: mute, destination: playPause)
        let plan = MicButtonRemap.plan(current: [other] + ours, active: false)
        #expect(plan.changed && plan.entries == [other])
        #expect(!MicButtonRemap.plan(current: [other], active: false).changed)
    }

    @Test("한/영 키 항목은 건드리지 않는다")
    func leavesCapsLock() {
        let capsLock = Entry(source: HIDRemap.capsLock, destination: HIDRemap.target)
        #expect(MicButtonRemap.plan(current: [capsLock], active: false).entries == [capsLock])
        #expect(MicButtonRemap.plan(current: [capsLock], active: true).entries == [capsLock] + ours)
    }
}
