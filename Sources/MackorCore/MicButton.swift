import Foundation

/// DJI Mic Mini·Mini 2 송신기 버튼을 Fn으로 바꾼다. Typeless처럼 Fn으로 받아쓰기를 켜고 끄는 앱을 마이크 버튼으로 쓰기 위해서다.
/// 수신기(RX)를 USB-C로 꽂으면 송신기 버튼이 수신기의 볼륨 올림(consumer 0xE9)으로 들어온다. 수신기에만 매핑하므로 키보드의
/// 볼륨 키는 그대로다. 한/영 키 매핑처럼 수신기를 다시 꽂으면 사라지므로 장치가 붙을 때마다 다시 건다.
public enum MicButtonRemap {
    /// DJI Technology Co., Ltd.
    public static let vendorID = 0x2CA3
    /// Wireless Mic Rx. Mic Mini와 Mic Mini 2가 같은 값을 쓴다.
    public static let productID = 0x4011
    /// Consumer 볼륨 올림(page 0x0C << 32 | usage 0xE9). 송신기 버튼이 이 키로 들어온다.
    static let volumeUp: UInt64 = 0xC_0000_00E9
    /// Consumer 볼륨 내림. 확인한 것은 올림뿐이지만 수신기에서 볼륨 키를 쓸 일은 없어 함께 바꾼다.
    static let volumeDown: UInt64 = 0xC_0000_00EA
    /// Fn(Apple 벤더 Top Case page 0xFF << 32 | usage 0x03). 이벤트 탭에는 keycode 63 flagsChanged로 들어온다.
    public static let fn: UInt64 = 0xFF_0000_0003
    static let sources = [volumeUp, volumeDown]

    public struct Plan: Equatable, Sendable {
        public var entries: [HIDRemap.Entry]
        public var changed: Bool
    }

    public static func isReceiver(vendorID: Int?, productID: Int?) -> Bool {
        vendorID == Self.vendorID && productID == Self.productID
    }

    /// 수신기 하나의 현재 매핑에서 우리 항목만 바꾼 결과를 계산한다. active가 false면 우리 항목을 지운다.
    /// 볼륨 키에 이미 다른 매핑이 있으면 덮어쓰지 않고, 다른 항목은 순서까지 그대로 둔다.
    public static func plan(current: [HIDRemap.Entry], active: Bool) -> Plan {
        var entries = current.filter { !isOurs($0) }
        if active {
            for source in sources where !entries.contains(where: { $0.source == source }) {
                entries.append(HIDRemap.Entry(source: source, destination: fn))
            }
        }
        return Plan(entries: entries, changed: Set(entries) != Set(current) || entries.count != current.count)
    }

    /// 볼륨 올림·내림 → Fn은 누가 넣었든 우리 것으로 본다.
    static func isOurs(_ entry: HIDRemap.Entry) -> Bool {
        entry.destination == fn && sources.contains(entry.source)
    }
}
