import AppKit
import Carbon
import MackorCore
import os

/// 입력 내용은 기록하지 않는다. 전환 번호·시간, 입력 소스 ID, 보류 개수만 남긴다.
/// 보기: /usr/bin/log stream --level debug --predicate 'subsystem == "io.mackor.app"' (zsh에서는 `log`가 셸 내장 명령이라 경로를 쓴다)
let log = Logger(subsystem: "io.mackor.app", category: "switch")

/// 한/영 키(Caps Lock → F18)를 누르는 순간 macOS의 입력 소스 전환 단축키를 보내고,
/// 전환이 실제로 끝날 때까지 뒤따르는 키를 붙잡았다가 원래 순서대로 내보낸다.
///
/// 보류분은 탭 콜백 안에서만 `CGEventTapPostEvent`로 내보낸다(우리 탭 바로 뒤, 받은 이벤트보다 앞).
/// 전환 완료는 메인 스레드의 알림·재확인이 알아채고, 그때 탭을 한 번 깨우는 배리어를 세션 입구로 보낸다.
/// 배리어든 그보다 먼저 온 키든 다음 탭 콜백이 보류분을 먼저 내보내므로, 탭을 지나는 순서가 곧 친 순서다.
final class SwitchEngine {
    /// 우리가 보낸 이벤트의 종류. eventSourceUserData의 아래 8비트에 넣는다.
    private enum Mark: Int64 {
        /// 전환 단축키. 탭에 들어오면 그대로 통과시킨다.
        case shortcut = 1
        /// 탭을 깨우는 F18 뗌. 탭에서 삼키고, 보류분을 내보낼 기회로 쓴다.
        case barrier = 2
        /// 탭 밖에서 HID 입구로 다시 보낸 보류분(예외 경로). 그대로 통과시킨다.
        case repost = 3
        /// 탭 자리에서 내보낸 보류분. 문서대로라면 우리 탭에 다시 오지 않는다.
        case tapPosted = 4
    }

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var gate = SwitchGate<CGEvent>()
    /// 전환을 시작하거나 보류를 비울 때마다 늘린다. 지난 전환의 재확인·시간 초과·배리어 기한을 무시하는 데 쓴다.
    private var generation = 0
    /// 우리가 보낸 이벤트 표식(eventSourceUserData). 위 56비트는 실행마다 정하는 난수, 아래 8비트는 `Mark`.
    private let tag = Int64.random(in: 1...(Int64.max >> 8)) << 8
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private var shortcut: SwitchShortcut? = .controlSpace
    /// 전환이 끝나(입력 소스 변경, 시간 초과, 단축키 없음, 입력 소스 하나) 탭을 깨운 시각. 그때부터 실제로 내보내기까지 걸린 시간을 기록한다.
    private var readyAt: TimeInterval?

    /// 배리어가 이 시간 안에 탭에 오지 않으면 탭 밖에서 내보낸다. 평소 왕복은 1ms 안쪽이다.
    private static let barrierTimeout: TimeInterval = 0.05
    /// 전환 중 입력 소스 재확인 간격.
    private static let pollInterval: TimeInterval = 0.005

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    /// 전환 단축키가 꺼져 있어 전환할 수 없는 상태.
    var shortcutMissing: Bool { shortcut == nil }

    /// 전환할 상대가 있는지(켜진 키보드 입력 소스가 2개 이상). 없으면 보류해 봐야 시간 초과까지 멈추기만 한다.
    private var hasAlternateSource = true

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
            self?.sourceChanged(via: "알림")
        }
        center.addObserver(forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main) { [weak self] _ in
            self?.countSources()
        }
        countSources()
    }

    private func countSources() {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        hasAlternateSource = sources.count >= 2
    }

    /// 접근성 권한이 있어야 성공한다.
    @discardableResult
    func start() -> Bool {
        if let tap, CFMachPortIsValid(tap) {
            // 꺼짐 알림 없이 꺼진 탭은 다시 켠다. 꺼진 채 두면 refresh()가 키 매핑까지 내린다.
            if !CGEvent.tapIsEnabled(tap: tap) {
                log.notice("꺼져 있던 이벤트 탭을 다시 켬")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return CGEvent.tapIsEnabled(tap: tap)
        }
        reloadShortcut()
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { proxy, type, event, info in
            let engine = Unmanaged<SwitchEngine>.fromOpaque(info!).takeUnretainedValue()
            return engine.handle(proxy: proxy, type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("이벤트 탭 시작")
        return true
    }

    func stop() {
        flush(reason: "중지")
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        tapSource = nil
    }

    /// 사용자가 시스템 설정에서 전환 단축키를 바꿨을 수 있으므로 전환할 때마다 다시 읽는다(읽기만 한다).
    private func reloadShortcut() {
        let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        shortcut = SwitchShortcut.resolve(symbolicHotKeys: hotKeys)
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: 탭 콜백

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 꺼진 동안 지나간 키는 이미 보류분을 앞질렀을 수 있다. 붙잡은 키를 잃지 않도록 탭 밖에서 모두 내보내고 다시 켠다.
            log.notice("이벤트 탭이 꺼져 다시 켬(\(type == .tapDisabledByTimeout ? "시간 초과" : "사용자 입력", privacy: .public))")
            flush(reason: "탭 재시작")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let step: SwitchGate<CGEvent>.Step
        let trigger: StaticString
        let data = event.getIntegerValueField(.eventSourceUserData)
        if data & ~0xFF == tag {
            switch Mark(rawValue: data & 0xFF) {
            case .barrier:
                step = gate.wake(now: now)
                trigger = "배리어"
            case .tapPosted:
                log.error("탭 자리에서 내보낸 이벤트가 탭에 다시 들어옴")
                return Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        } else if type != .flagsChanged,
                  UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)) == ToggleKeyCode.f18 {
            // 한/영 키는 누르는 순간 한 번만 전환하고, 자동 반복과 뗌은 삼킨다(끝난 전환의 보류분을 내보낼 기회로는 쓴다).
            let press = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
            step = press ? gate.toggle(now: now, current: Self.currentSourceID()) : gate.wake(now: now)
            trigger = "한/영 키"
        } else if gate.isIdle {
            // 평소 경로: 복사도 입력 소스 조회도 하지 않는다.
            return Unmanaged.passUnretained(event)
        } else {
            step = gate.receive(event.copy() ?? event, now: now)
            trigger = "다음 키"
        }
        perform(step, proxy: proxy, trigger: trigger)
        return step.passes ? Unmanaged.passUnretained(event) : nil
    }

    /// 탭 콜백 안에서만 부른다: 보류분을 우리 탭 바로 뒤에 순서대로 넣고(받은 이벤트보다 앞선다), 필요하면 다음 전환을 시작한다.
    /// proxy는 이 콜백의 것이라 콜백 밖에서는 쓰지 않는다.
    private func perform(_ step: SwitchGate<CGEvent>.Step, proxy: CGEventTapProxy, trigger: StaticString) {
        for event in step.release {
            // 다른 도구가 붙인 표식은 지우지 않는다. 표식 없는 키에만 붙여, 혹시 탭에 다시 들어오면 알아챈다.
            if event.getIntegerValueField(.eventSourceUserData) == 0 { mark(event, .tapPosted) }
            event.tapPostEvent(proxy)
        }
        if !step.release.isEmpty {
            let waited = readyAt.map { (now - $0) * 1000 } ?? 0
            log.debug("보류 \(step.release.count)개 내보냄(\(trigger, privacy: .public), 완료 후 \(waited, format: .fixed(precision: 1))ms)")
        }
        if !gate.isReady { readyAt = nil }
        if step.switchAgain { beginSwitch() }
    }

    // MARK: 탭 밖(알림, 재확인, 타이머)

    /// 전환 단축키를 HID 입구로 보낸다(시스템 단축키로 처리되는 검증된 경로).
    /// 탭 콜백 안에서 부르면 방금 탭 자리에 넣은 보류분보다 반드시 뒤에 처리된다.
    private func beginSwitch() {
        reloadShortcut()
        generation += 1
        let current = generation
        guard let shortcut else {
            log.error("입력 소스 전환 단축키가 꺼져 있습니다")
            if gate.expire(current: Self.currentSourceID()) { wakeTap() }
            return
        }
        post(shortcut)
        guard hasAlternateSource else {
            if gate.expire(current: Self.currentSourceID()) { wakeTap() }
            return
        }
        if case .switching(let from, _) = gate.phase {
            log.debug("전환 #\(current) 시작: \(from, privacy: .public)에서, 보류 \(self.gate.heldCount)개")
        }
        pollUntilSwitched(generation: current)
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitchGate<CGEvent>.timeout) { [weak self] in
            guard let self, self.generation == current, self.gate.isTimedOut(now: self.now) else { return }
            let source = Self.currentSourceID()
            log.notice("전환 #\(current) 시간 초과: 입력 소스가 \(source, privacy: .public)에서 바뀌지 않아 보류한 키를 그대로 내보냄")
            if self.gate.expire(current: source) { self.wakeTap() }
        }
    }

    /// 알림을 받은 순간 이 프로세스의 입력 소스 조회 값이 아직 갱신되지 않았을 수 있다.
    /// 전환 중에는 5ms마다 직접 확인해서 알림 순서와 무관하게 완료를 잡는다.
    private func pollUntilSwitched(generation current: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            guard let self, self.generation == current, self.gate.isSwitching else { return }
            self.sourceChanged(via: "확인")
            if self.generation == current, self.gate.isSwitching { self.pollUntilSwitched(generation: current) }
        }
    }

    /// 입력 소스 변경 알림 또는 재확인: 실제로 바뀌었으면 전환 완료로 표시하고 탭을 깨운다(보류분은 탭 안에서 나간다).
    private func sourceChanged(via path: StaticString) {
        let current = Self.currentSourceID()
        guard case .switching(let from, let since) = gate.phase else {
            // 시간 초과 뒤에야 끝난 전환, 다른 앱이 바꾼 경우 등. 진단용.
            if gate.isIdle { log.debug("전환 중이 아닐 때 입력 소스 변경(\(path, privacy: .public)): \(current, privacy: .public)") }
            return
        }
        guard gate.sourceChanged(to: current) else { return }
        log.debug("전환 #\(self.generation) 완료(\(path, privacy: .public)): \(Int((self.now - since) * 1000))ms, \(from, privacy: .public) → \(current, privacy: .public), 보류 \(self.gate.heldCount)개")
        wakeTap()
    }

    /// 보류분은 탭 콜백 안에서만 내보내므로 표식 붙은 배리어로 탭을 한 번 깨운다. 그 전에 다른 키가 먼저 탭에 오면
    /// 그 콜백이 내보내고, 뒤늦게 온 배리어는 삼키기만 한다. 탭이 꺼졌거나 보안 입력 중이면(탭이 키를 못 본다)
    /// 배리어가 오지 않으므로 바로 탭 밖에서 내보낸다.
    private func wakeTap() {
        readyAt = now
        guard let tap, CGEvent.tapIsEnabled(tap: tap), !IsSecureEventInputEnabled() else {
            return releaseOutsideTap(reason: "탭을 쓸 수 없음")
        }
        postBarrier()
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.barrierTimeout) { [weak self] in
            guard let self, self.generation == current, self.gate.isReady else { return }
            self.releaseOutsideTap(reason: "배리어가 돌아오지 않음")
        }
    }

    /// 세션 입구로 보낸다: HID 단계의 다른 앱 탭을 거치지 않고 우리 탭에 온다.
    /// F18 뗌이라 표식이 지워져 와도 삼켜지고, 탭이 꺼진 순간 앱으로 새어도 아무 일도 하지 않는다.
    private func postBarrier() {
        guard let barrier = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(ToggleKeyCode.f18), keyDown: false) else { return }
        barrier.flags = CGEventSource.flagsState(.combinedSessionState)
        mark(barrier, .barrier)
        barrier.post(tap: .cgSessionEventTap)
    }

    /// 탭 콜백을 기다릴 수 없을 때(탭이 꺼짐, 보안 입력, 배리어 분실) 보류분을 HID 입구로 다시 보낸다.
    /// 이때는 이미 탭 앞에 와 있던 키가 앞지를 수 있다(예전 방식). 드문 예외 경로라 기록을 남긴다.
    private func releaseOutsideTap(reason: StaticString) {
        let step = gate.wake(now: now)
        for event in step.release { repost(event) }
        readyAt = nil
        log.notice("탭 밖에서 보류 \(step.release.count)개 내보냄(\(reason, privacy: .public))")
        if step.switchAgain { beginSwitch() }
    }

    /// 보류를 전환 없이 끝내고 붙잡은 키를 HID 입구로 다시 보낸다(중지, 탭 꺼짐). 대기 중이던 전환 키는 버린다.
    private func flush(reason: StaticString) {
        generation += 1
        readyAt = nil
        let events = gate.flush()
        for event in events { repost(event) }
        log.debug("보류 비움(\(reason, privacy: .public)): \(events.count)개")
    }

    static func currentSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private func mark(_ event: CGEvent, _ mark: Mark) {
        event.setIntegerValueField(.eventSourceUserData, value: tag | mark.rawValue)
    }

    private func repost(_ event: CGEvent) {
        mark(event, .repost)
        event.post(tap: .cghidEventTap)
    }

    /// 전환 단축키를 키 순서 그대로 합성한다. 누르고 있는 다른 수정키는 섞지 않아야 단축키가 정확히 일치한다.
    /// 기능키 단축키(예: F18)의 fn 표시는 하드웨어 기능키처럼 단축키 키의 누름·뗌에만 붙인다.
    private func post(_ shortcut: SwitchShortcut) {
        var flags: UInt64 = 0
        var events: [CGEvent] = []
        func key(_ code: UInt16, down: Bool, extraFlags: UInt64 = 0) {
            guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { return }
            event.flags = CGEventFlags(rawValue: flags | extraFlags)
            events.append(event)
        }
        for modifier in shortcut.modifiers {
            flags |= modifier.flag
            key(modifier.keyCode, down: true)
        }
        key(shortcut.keyCode, down: true, extraFlags: shortcut.keyFlags)
        key(shortcut.keyCode, down: false, extraFlags: shortcut.keyFlags)
        for modifier in shortcut.modifiers.reversed() {
            flags &= ~modifier.flag
            key(modifier.keyCode, down: false)
        }
        for event in events {
            mark(event, .shortcut)
            event.post(tap: .cghidEventTap)
        }
    }
}
