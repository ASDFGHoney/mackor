import AppKit
import IOKit
import IOKit.hidsystem
import MackorCore

/// Caps Lock을 HID 단계에서 F18로 바꾼다(hidutil과 같은 공개 IOKit API, 권한 불필요). 켜져 있던 Caps Lock은 끈다.
/// HID 매핑은 재부팅이나 키보드 재연결 때 사라지므로 시작, 새 키보드 연결, 잠자기 해제 때 다시 적용한다.
/// 종료할 때는 mackor 항목만 지워 원래 키로 되돌린다.
/// DJI 마이크 수신기가 꽂혀 있으면 송신기 버튼을 Fn으로 바꾸는 매핑도 같은 방식으로 건다(MicButtonRemap).
final class KeyRemapper {
    static let shared = KeyRemapper()

    /// 간이 클라이언트는 만든 때의 서비스 목록만 돌려준다(그 뒤에 연결한 키보드·수신기가 빠진다). 목록을 새로 받는 함수는
    /// 공개되어 있지 않아 services()가 부를 때마다 새로 만든다. 찾은 서비스를 쓰는 동안 놓이지 않도록 마지막 것을 붙잡아 둔다.
    private var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var notificationPort: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var pendingApply: DispatchWorkItem?
    /// Caps Lock을 한/영 키로 쓸 수 없는 키보드와 그 이유.
    private(set) var conflicts: [KeyConflict] = []

    /// false면 우리 매핑을 지우고 걸지 않는다(권한이 없어 한/영 키를 처리할 수 없을 때나, 빠른 사용자 전환으로
    /// 다른 사용자가 쓰는 동안 Caps Lock을 망가뜨리지 않기 위해).
    var isActive = false {
        didSet { if isActive != oldValue { apply() } }
    }
    /// false면 DJI 수신기의 버튼 → Fn 매핑을 지우고 걸지 않는다. 한/영 키와 따로 움직인다:
    /// 이벤트 탭을 거치지 않으므로 접근성 권한이나 보안 입력과 상관없이 동작한다.
    var isMicButtonActive = false {
        didSet { if isMicButtonActive != oldValue { writeMicButton(active: isMicButtonActive) } }
    }
    /// DJI 수신기가 꽂혀 있는지. 메뉴에 켜고 끄는 항목을 이때만 보인다.
    var hasMicReceiver: Bool { !micReceivers().isEmpty }
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        observeNewDevices()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleApply(after: 1.0)
        }
    }

    /// 모든 키보드에 Caps Lock → F18 매핑을, DJI 수신기에 버튼 → Fn 매핑을 적용한다(비활성이면 지운다).
    /// 매핑이 이미 맞으면 쓰지 않는다.
    func apply() {
        write(active: isActive)
        writeMicButton(active: isMicButtonActive)
    }

    /// 종료 시: 우리 항목만 지운다.
    func remove() {
        write(active: false)
        writeMicButton(active: false)
    }

    private func write(active: Bool) {
        // --no-remap(개발·검증)은 쓰기도 지우기도 하지 않는다. 설치본과 함께 떠 있어도 그 매핑을 건드리지 않기 위해서다.
        guard Settings.shared.remapEnabled else { return }
        var conflicts: [KeyConflict] = []
        var addedCapsLock = false
        for service in keyboards() {
            guard let current = mappings(of: service) else {
                NSLog("mackor: %@의 키 매핑을 읽지 못해 건너뜁니다", name(of: service))
                continue
            }
            let plan = HIDRemap.plan(current: current, active: active)
            var conflict: KeyConflict?
            if plan.conflict != nil {
                conflict = KeyConflict(keyboard: name(of: service), reason: .otherMapping)
            } else if active, HIDRemap.isCapsLockRemapped(modifierPairs: modifierPairs(of: service)) {
                // 가려져도 우리 항목은 평소대로 넣는다. 사용자가 보조 키를 되돌리는 즉시 동작한다.
                conflict = KeyConflict(keyboard: name(of: service), reason: .modifierKey)
            }
            // 인터페이스가 여럿인 키보드는 같은 이름의 서비스가 여럿이라 한 번만 알린다.
            if let conflict, !conflicts.contains(conflict) { conflicts.append(conflict) }
            guard plan.changed else { continue }
            let value = plan.entries.map(\.dictionary) as CFArray
            guard IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, value) else {
                NSLog("mackor: %@에 키 매핑을 쓰지 못했습니다", name(of: service))
                continue
            }
            if plan.addsCapsLock { addedCapsLock = true }
        }
        self.conflicts = conflicts
        // 대문자 고정은 키보드마다의 상태를 합친 것이라, 한 키보드에만 새로 걸었어도 모든 키보드에서 끈다.
        // 매핑이 이미 있었으면 건드리지 않는다(사용자가 다른 방법으로 일부러 켠 것을 매번 끄지 않기 위해).
        if addedCapsLock { turnOffCapsLock() }
    }

    /// 매핑한 뒤에는 Caps Lock으로 대문자 고정을 풀 수 없다(UserKeyMapping은 켜진 상태를 끄지 않는다).
    /// 켜져 있는 키보드를 끈다. LED도 함께 꺼지고, 잠시 뒤 Caps Lock 해제 flagsChanged가 한 번 온다.
    private func turnOffCapsLock() {
        let key = kIOHIDServiceCapsLockStateKey as CFString
        for service in keyboards() where IOHIDServiceClientCopyProperty(service, key) as? Bool == true {
            if IOHIDServiceClientSetProperty(service, key, kCFBooleanFalse) {
                log.info("Caps Lock이 켜져 있어 껐습니다")
            } else {
                NSLog("mackor: %@의 Caps Lock을 끄지 못했습니다", name(of: service))
            }
        }
    }

    private func services() -> [IOHIDServiceClient] {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
    }

    private func keyboards() -> [IOHIDServiceClient] {
        services().filter { IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 }
    }

    /// DJI 수신기마다 버튼 → Fn 매핑을 걸거나(active) 우리 항목을 지운다. 이미 맞으면 쓰지 않는다.
    private func writeMicButton(active: Bool) {
        guard Settings.shared.remapEnabled else { return }
        for service in micReceivers() {
            guard let current = mappings(of: service) else {
                NSLog("mackor: %@의 키 매핑을 읽지 못해 건너뜁니다", name(of: service))
                continue
            }
            let plan = MicButtonRemap.plan(current: current, active: active)
            guard plan.changed else { continue }
            if IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, plan.entries.map(\.dictionary) as CFArray) {
                log.info("DJI 마이크 버튼 → Fn \(active ? "켬" : "끔", privacy: .public)")
            } else {
                NSLog("mackor: %@에 키 매핑을 쓰지 못했습니다", name(of: service))
            }
        }
    }

    /// 꽂혀 있는 DJI 수신기. 키보드가 아니라 consumer 장치라 keyboards()에 들지 않는다.
    private func micReceivers() -> [IOHIDServiceClient] {
        services().filter {
            MicButtonRemap.isReceiver(vendorID: IOHIDServiceClientCopyProperty($0, kIOHIDVendorIDKey as CFString) as? Int,
                                      productID: IOHIDServiceClientCopyProperty($0, kIOHIDProductIDKey as CFString) as? Int)
        }
    }

    /// 읽을 수 없는 항목이 섞여 있으면 nil: 모르는 매핑을 지우지 않도록 그 키보드는 건너뛴다.
    private func mappings(of service: IOHIDServiceClient) -> [HIDRemap.Entry]? {
        guard let raw = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) else { return [] }
        guard let list = raw as? [[String: Any]] else { return nil }
        let entries = list.compactMap(HIDRemap.Entry.init(dictionary:))
        return entries.count == list.count ? entries : nil
    }

    /// 시스템 설정 › 키보드 › 키보드 단축키 › 보조 키의 설정(HIDKeyboardModifierMappingPairs). 간이 클라이언트는
    /// 이 속성을 주지 않으므로(nil) 커널 레지스트리의 미러에서 읽는다. 읽지 못하면 빈 목록, 곧 가리지 않는 것으로 본다.
    private func modifierPairs(of service: IOHIDServiceClient) -> [HIDRemap.Entry] {
        guard let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { return [] }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard entry != 0 else { return [] }
        defer { IOObjectRelease(entry) }
        let properties = IORegistryEntryCreateCFProperty(entry, "HIDEventServiceProperties" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        let pairs = properties?["HIDKeyboardModifierMappingPairs"] as? [[String: Any]] ?? []
        return pairs.compactMap(HIDRemap.Entry.init(dictionary:))
    }

    /// 시스템 설정의 키보드 화면. 보조 키 화면의 ‘키보드 선택’은 제품명을 이 번들의 번역 표로 옮겨 보여 준다.
    private static let keyboardSettings = Bundle(path: "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex")

    /// 보조 키 화면의 ‘키보드 선택’과 같은 이름(예: Apple Internal Keyboard / Trackpad → Apple 내장 키보드 / 트랙패드).
    /// 번역이 없는 제품명(대부분의 외장 키보드)은 그대로 쓴다.
    private func name(of service: IOHIDServiceClient) -> String {
        guard let product = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String else { return "키보드" }
        return Self.keyboardSettings?.localizedString(forKey: product, value: product, table: nil) ?? product
    }

    /// delay 뒤에 한 번 다시 적용한다. 그 전에 다시 부르면 앞의 예약은 취소한다.
    /// 그때 비활성인 쪽(한/영 키와 마이크 버튼 각각)은 아무것도 쓰지 않는다. 우리 항목은 비활성이 될 때 이미 지웠고,
    /// 지금 있는 Caps Lock → F18은 앞에 있는 다른 사용자의 mackor나 사용자가 직접 건 것일 수 있다(잠자기 해제·장치 연결마다 지우면 그 매핑이 사라진다).
    func scheduleApply(after delay: TimeInterval) {
        pendingApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isActive { self.write(active: true) }
            if self.isMicButtonActive { self.writeMicButton(active: true) }
        }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 새 HID 서비스가 생기면(키보드·DJI 수신기 연결, 블루투스 재연결) 다시 적용한다. 레지스트리 알림이라 입력 모니터링 권한이 필요 없다.
    private func observeNewDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOHIDEventService"), { context, iterator in
            KeyRemapper.drain(iterator)
            guard let context else { return }
            // 서비스가 이벤트 시스템에 붙기까지 잠깐 걸린다.
            Unmanaged<KeyRemapper>.fromOpaque(context).takeUnretainedValue().scheduleApply(after: 0.5)
        }, context, &iterator)
        // 이미 있는 장치를 비워야 알림이 활성화된다.
        if result == KERN_SUCCESS { Self.drain(iterator) }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 { IOObjectRelease(object) }
    }
}

/// Caps Lock을 한/영 키로 쓸 수 없는 키보드와 그 이유.
struct KeyConflict: Hashable {
    enum Reason: Hashable {
        /// Caps Lock에 다른 앱이나 hidutil이 넣은 키 매핑이 있다. mackor는 덮어쓰지 않는다.
        case otherMapping
        /// 시스템 설정의 보조 키에서 Caps Lock을 다른 동작으로 바꿔 두었다. 이 설정이 먼저 적용되어 매핑이 가려진다.
        case modifierKey
    }

    var keyboard: String
    var reason: Reason

    /// 무엇이 문제인지(메뉴 첫 줄, 설정 도우미 경고 앞부분).
    var problem: String {
        switch reason {
        case .otherMapping: "Caps Lock에 다른 키 매핑이 있어 동작하지 않습니다"
        case .modifierKey: "보조 키 설정에서 Caps Lock이 다른 동작으로 바뀌어 있습니다"
        }
    }

    /// 어떻게 풀지(메뉴 둘째 줄, 설정 도우미 경고 뒷부분).
    var remedy: String {
        switch reason {
        case .otherMapping: "다른 앱이나 hidutil로 넣은 Caps Lock 매핑을 지우면 적용됩니다"
        case .modifierKey: "시스템 설정 › 키보드 › 키보드 단축키 › 보조 키에서 ‘⇪ Caps Lock’으로 되돌리면 적용됩니다"
        }
    }
}
