import AppKit
import Carbon
import MackorCore
import ServiceManagement
import SwiftUI

/// 설정 도우미가 앱에 부탁하는 일.
protocol OnboardingHost: AnyObject {
    /// 키 매핑을 다시 적용한다(다른 앱의 매핑이 지워졌거나 보조 키 설정이 되돌려졌을 수 있다). Caps Lock을 한/영 키로 쓸 수 없는 키보드와 그 이유를 돌려준다.
    func reapplyKeyMapping() -> [KeyConflict]
    /// 메뉴 막대 아이콘을 잠깐 깜빡여 위치를 알려 준다.
    func highlightStatusItem()
    func onboardingVisibilityChanged()
}

/// 처음 실행하거나 권한이 없을 때 띄우는 설정 도우미 창: 소개 → 권한 허용 → 써 보기 → 완료.
final class OnboardingController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var flow = OnboardingFlow(start: .welcome, trusted: false)
    @Published private(set) var hint = PermissionHint.none
    @Published var showsTroubleshooting = false
    @Published private(set) var inputSource = InputSourceInfo.current()
    /// 써 보기 단계에서 입력 소스가 바뀌는 것을 본 적이 있다.
    @Published private(set) var sawSwitch = false
    @Published private(set) var conflicts: [KeyConflict] = []
    @Published private(set) var shortcutMissing = false
    @Published private(set) var singleSource = false
    @Published private(set) var loginItem = LoginItem.State.unavailable

    weak var host: OnboardingHost?
    private var window: NSWindow?

    override init() {
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
            self?.inputSourceChanged()
        }
        center.addObserver(forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main) { [weak self] _ in
            self?.refreshChecks()
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// 설정 도우미를 연다. 이미 열려 있으면 진행 중인 흐름은 두고 앞으로 가져온다(다른 단계를 콕 집은 경우는 그 단계로).
    /// - Parameter activate: false면 포커스를 뺏지 않고 창만 띄운다(실행 중 권한이 꺼졌을 때).
    func show(at step: OnboardingStep, permissionLost: Bool, activate: Bool = true) {
        if !isVisible || (step != .welcome && step != flow.step) {
            flow = OnboardingFlow(start: step, trusted: Accessibility.isTrusted, permissionLost: permissionLost)
            hint = .none
            showsTroubleshooting = false
            stepDidChange(from: nil)
        }
        let window = window ?? makeWindow()
        if !window.isVisible { window.center() }
        if activate { bringToFront() } else { window.orderFrontRegardless() }
        host?.onboardingVisibilityChanged()
    }

    /// 앱이 권한을 확인할 때마다(열려 있으면 0.25초) 부른다.
    func update(trusted: Bool) {
        guard isVisible else { return }
        mutate { $0.trustChanged(trusted) }
        let hint = flow.hint(now: ProcessInfo.processInfo.systemUptime,
                             lastTrustedRequirement: Settings.shared.lastTrustedRequirement,
                             currentRequirement: Accessibility.designatedRequirement)
        guard hint != self.hint else { return }
        self.hint = hint
        if hint != .none { showsTroubleshooting = true }
    }

    // MARK: 동작

    func next() { mutate { $0.next() } }

    func back() { mutate { $0.back() } }

    func requestPermission() {
        mutate { $0.requestPermission(now: ProcessInfo.processInfo.systemUptime) }
        Accessibility.request()
        // 시스템 설정에 가려지지 않도록 허용될 때까지 위에 띄워 둔다.
        window?.level = .floating
    }

    func setLoginItem(_ enabled: Bool) {
        LoginItem.set(enabled)
        loginItem = LoginItem.state
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: 흐름

    private func mutate(_ change: (inout OnboardingFlow) -> Void) {
        var next = flow
        change(&next)
        guard next != flow else { return }
        let old = flow.step
        flow = next
        if flow.isFinished {
            Settings.shared.didSetUp = true
            window?.close()
        } else if flow.step != old {
            stepDidChange(from: old)
        }
    }

    private func stepDidChange(from old: OnboardingStep?) {
        switch flow.step {
        case .welcome, .permission:
            break
        case .tryIt:
            sawSwitch = false
            conflicts = host?.reapplyKeyMapping() ?? []
            inputSource = InputSourceInfo.current()
            refreshChecks()
            // 시스템 설정에서 허용하자마자 넘어왔다: 창을 다시 앞으로 가져와 바로 써 볼 수 있게 한다.
            if old == .permission, window?.level == .floating { bringToFront() }
        case .done:
            loginItem = LoginItem.state
            host?.highlightStatusItem()
        }
    }

    // MARK: 써 보기

    /// 알림을 받은 순간에는 조회 값이 아직 이전 입력 소스일 수 있어 잠시 뒤 한 번 더 읽는다.
    private func inputSourceChanged() {
        guard isVisible else { return }
        readInputSource()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.readInputSource() }
    }

    private func readInputSource() {
        let current = InputSourceInfo.current()
        guard current != inputSource else { return }
        if flow.step == .tryIt { sawSwitch = true }
        inputSource = current
    }

    /// 전환이 될 수 없는 설정(전환 단축키 꺼짐, 입력 소스 하나뿐)을 확인한다. 읽기만 한다.
    private func refreshChecks() {
        let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        shortcutMissing = SwitchShortcut.resolve(symbolicHotKeys: hotKeys) == nil
        singleSource = InputSourceInfo.selectableCount() < 2
    }

    // MARK: 창

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        let hosting = NSHostingController(rootView: OnboardingView(controller: self))
        // 제목 막대까지 내용으로 쓰므로(투명 제목 막대) 안전 영역을 더한 크기가 아니라 뷰 크기 그대로 둔다.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(OnboardingView.size)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "mackor 설정 도우미"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    private func bringToFront() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 허용을 마치고 사용자가 돌아왔다: 더는 다른 창 위에 떠 있을 필요가 없다.
        if flow.step != .permission || flow.trusted { window?.level = .normal }
        if flow.step == .done { loginItem = LoginItem.state }
        // 다른 앱의 Caps Lock 매핑이나 보조 키 설정을 바꾸고 돌아왔을 수 있다(원인을 없앴거나 새로 생김). 이미 맞으면 쓰지 않는다.
        if flow.step == .tryIt { conflicts = host?.reapplyKeyMapping() ?? [] }
        refreshChecks()
    }

    func windowWillClose(_ notification: Notification) {
        window?.level = .normal
        // 닫히는 중에는 아직 보이는 상태라 다음 차례에 알린다.
        DispatchQueue.main.async { [weak self] in self?.host?.onboardingVisibilityChanged() }
    }
}

/// 현재 키보드 입력 소스(설정 도우미 표시용).
struct InputSourceInfo: Equatable {
    var id: String
    var name: String
    var isKorean: Bool

    static func current() -> InputSourceInfo {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return InputSourceInfo(id: "", name: "알 수 없음", isKorean: false)
        }
        let id = property(source, kTISPropertyInputSourceID) as? String ?? ""
        let languages = property(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        return InputSourceInfo(id: id, name: property(source, kTISPropertyLocalizedName) as? String ?? id,
                               isKorean: languages.first == "ko")
    }

    /// 켜져 있어 전환할 수 있는 키보드 입력 소스 수.
    static func selectableCount() -> Int {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.count ?? 0
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
}
