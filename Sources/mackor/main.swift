import AppKit
import MackorCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, OnboardingHost {
    private let engine = SwitchEngine()
    private let remapper = KeyRemapper.shared
    private let onboarding = OnboardingController()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var trustWatch = TrustWatch()
    /// 이 사용자의 세션이 앞에 있는지. 빠른 사용자 전환으로 다른 사용자가 쓰는 동안에는 false다.
    private var sessionActive = true
    /// 보안 입력이 켜져 있는지. 그동안에는 이벤트 탭이 F18을 보지 못하므로 매핑을 풀어 macOS 기본 Caps Lock 전환에 맡긴다.
    private var secureInput = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        // 항목마다 정한 isEnabled를 그대로 쓴다(자동 활성화는 개발 실행의 "로그인 시 자동 실행"까지 켜 버린다).
        menu.autoenablesItems = false
        statusItem?.menu = menu
        installMainMenu()
        onboarding.host = self
        registerLoginItemOnce()
        remapper.start()
        observeSession()
        refresh()
        // 권한 없이 시작하면 isActive가 false 그대로라 위에서 아무것도 쓰지 않는다. 비정상 종료로 남은 매핑이 있으면
        // Caps Lock이 먹통이므로 한 번 정리한다(실행 직후엔 이 사용자의 세션이 앞에 있어 다른 사용자의 매핑이 아니다).
        if !remapper.isActive { remapper.apply() }
        // 권한이 없으면 시스템 대화상자를 바로 띄우지 않고, 설정 도우미로 이유부터 설명한다.
        // 대화상자는 도우미의 "접근성 권한 허용" 버튼을 눌렀을 때 뜬다.
        let settings = Settings.shared
        if let step = settings.onboardingStart ?? OnboardingFlow.launchStep(trusted: Accessibility.isTrusted, didSetUp: settings.didSetUp) {
            onboarding.show(at: step, permissionLost: settings.didSetUp)
        }
        schedulePermissionTimer()
        watchSecureInput()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        // 다른 사용자가 쓰는 동안에는 지우지 않는다. 우리 항목은 뒤로 갈 때 이미 지웠고, 지금 있는 매핑은 그 사용자의 mackor 것일 수 있다.
        if sessionActive { remapper.remove() }
    }

    /// 메뉴 막대 아이콘이 가려져 보이지 않을 때(노치, 공간 부족)도 앱을 다시 실행하면 설정 도우미가 뜬다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOnboarding()
        return false
    }

    /// 권한 상태에 맞춰 이벤트 탭과 키 매핑을 켜고 끈다. 탭 없이 매핑만 켜면 Caps Lock이 아무 일도 하지 않게 되므로 함께 움직인다.
    /// 다른 사용자가 쓰는 동안(빠른 사용자 전환)이나 보안 입력 중(탭이 키를 못 본다)에는 매핑만 푼다.
    private func refresh() {
        let trusted = Accessibility.isTrusted
        if trusted, !engine.isRunning { engine.start() }
        if !trusted, engine.isRunning { engine.stop() }
        updateSecureInput()
        remapper.isMicButtonActive = sessionActive && Settings.shared.micButtonEnabled
        remapper.isActive = engine.isRunning && sessionActive && !secureInput
        updateIcon()
        if trusted { rememberTrust() }
        if trustWatch.update(trusted) == .revoked {
            // 실행 중에 권한이 꺼져 한/영 키가 멈췄다(매핑도 풀려 Caps Lock은 원래대로다). 권한 단계로 안내하되 포커스는 뺏지 않는다.
            onboarding.show(at: .permission, permissionLost: true, activate: false)
        }
        onboarding.update(trusted: trusted)
    }

    /// 권한은 실행 중에도 켜지거나 꺼질 수 있다. 평소엔 1초, 설정 도우미가 열려 있으면 허용을 바로 알아채도록 0.25초마다 확인한다.
    private func schedulePermissionTimer() {
        let interval: TimeInterval = onboarding.isVisible ? 0.25 : 1
        guard permissionTimer?.timeInterval != interval else { return }
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// 보안 입력은 알림이 없어 0.25초마다 확인한다. 켜진 뒤 매핑을 풀기 전까지는 Caps Lock이 아무 일도 하지 않으므로
    /// 권한 확인(1초)보다 짧게 둔다. 바뀌었을 때만 refresh()로 매핑을 고친다.
    private func watchSecureInput() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, SecureInput.isEnabled != self.secureInput else { return }
            self.refresh()
        }
        timer.tolerance = 0.05
    }

    /// 보안 입력이 켜지고 꺼지는 것을 기록한다. 뒤에 있는 앱이 켜 둔 채 남겨 두면 어느 앱에서든 F18이 막히므로 켠 앱을 남긴다.
    private func updateSecureInput() {
        let enabled = SecureInput.isEnabled
        guard enabled != secureInput else { return }
        secureInput = enabled
        if enabled {
            log.notice("보안 입력 켜짐(\(SecureInput.ownerName ?? "알 수 없는 앱", privacy: .public)): Caps Lock을 macOS 기본 전환에 맡김")
        } else {
            log.notice("보안 입력 꺼짐: Caps Lock을 다시 mackor가 처리")
        }
    }

    /// 권한이 있는 동안의 서명을 기억해 둔다. 나중에 서명이 바뀌어 권한 항목이 낡으면 설정 도우미가 알아챈다.
    private func rememberTrust() {
        let settings = Settings.shared
        if !settings.didSetUp { settings.didSetUp = true }
        guard settings.isAppBundle, let requirement = Accessibility.designatedRequirement,
              settings.lastTrustedRequirement != requirement else { return }
        settings.lastTrustedRequirement = requirement
    }

    private func updateIcon() {
        let conflicted = !remapper.conflicts.isEmpty
        let symbol = engine.isRunning && !conflicted ? "keyboard" : "keyboard.badge.exclamationmark"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "mackor")
        statusItem?.button?.toolTip = !engine.isRunning ? "mackor: 접근성 권한이 필요합니다"
            : conflicted ? "mackor: Caps Lock을 한/영 키로 쓸 수 없는 키보드가 있습니다"
            : secureInput ? "mackor: 보안 입력 중이라 macOS 기본 Caps Lock 전환을 씁니다" : "mackor: Caps Lock으로 한/영 전환"
    }

    /// 빠른 사용자 전환: HID 매핑은 장치 단위라 이 맥의 모든 사용자에게 걸린다. 다른 사용자가 쓰는 동안에는 매핑을 푼다.
    /// 이벤트 탭은 그대로 둔다(세션 탭이라 다른 사용자의 키는 보지 않는다).
    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sessionActive = false
            self.refresh()
        }
        center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sessionActive = true
            self.refresh()
            // 다른 사용자의 mackor가 나가며 지운 매핑을 다시 건다.
            self.remapper.scheduleApply(after: 1)
        }
    }

    private func registerLoginItemOnce() {
        guard Settings.shared.isAppBundle, !Settings.shared.didOfferLoginItem else { return }
        Settings.shared.didOfferLoginItem = true
        try? SMAppService.mainApp.register()
    }

    // MARK: 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        // 매핑을 건 뒤에 원인이 생기거나 없어졌을 수 있으니(보조 키 설정, 다른 앱의 Caps Lock 매핑, 지워진 우리 항목)
        // 열 때마다 다시 적용해 본다(이미 맞으면 쓰지 않는다).
        if remapper.isActive {
            remapper.apply()
            updateIcon()
        }
        menu.removeAllItems()
        if engine.isRunning {
            menu.addItem(label("Caps Lock으로 한/영 전환 중"))
        } else {
            menu.addItem(item("접근성 권한 허용하기…", #selector(showPermissionStep)))
            menu.addItem(label(Settings.shared.didSetUp ? "⚠︎ 접근성 권한이 꺼져 있어 Caps Lock이 원래대로 돌아갔습니다"
                                                        : "mackor로 Caps Lock 한/영 전환을 쓰려면 macOS 접근성 권한이 필요합니다"))
        }
        if engine.isRunning, secureInput {
            // 아이콘은 그대로 둔다. 비밀번호를 칠 때마다 켜졌다 꺼지므로 아이콘까지 바꾸면 깜박인다.
            menu.addItem(label("⚠︎ 보안 입력이 켜져 있어 macOS 기본 Caps Lock 전환을 쓰는 중입니다"))
            if let owner = SecureInput.ownerName {
                menu.addItem(label("   켠 앱: \(owner) — 그 앱의 비밀번호 칸을 벗어나거나 앱을 다시 열면 돌아옵니다"))
            } else {
                menu.addItem(label("   비밀번호 칸을 벗어나거나 보안 입력을 켠 앱을 다시 열면 돌아옵니다"))
            }
        }
        if engine.shortcutMissing {
            menu.addItem(label("⚠︎ 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스에서"))
            menu.addItem(label("   ‘이전 입력 소스 선택’을 켜 주세요"))
        }
        for conflict in remapper.conflicts {
            menu.addItem(label("⚠︎ \(conflict.keyboard): \(conflict.problem)"))
            menu.addItem(label("   \(conflict.remedy)"))
        }
        menu.addItem(.separator())

        let login = item("로그인 시 자동 실행", #selector(toggleLoginItem))
        login.state = LoginItem.state == .enabled ? .on : .off
        login.isEnabled = Settings.shared.isAppBundle
        menu.addItem(login)
        if remapper.hasMicReceiver {
            let mic = item("DJI 마이크 버튼을 Fn 키로", #selector(toggleMicButton))
            mic.state = Settings.shared.micButtonEnabled ? .on : .off
            menu.addItem(mic)
        }
        menu.addItem(item("설정 도우미…", #selector(showOnboarding)))
        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(label("mackor \(version)"))
        menu.addItem(item("종료", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleLoginItem() {
        LoginItem.set(LoginItem.state != .enabled)
    }

    @objc private func toggleMicButton() {
        Settings.shared.micButtonEnabled.toggle()
        refresh()
    }

    @objc private func showOnboarding() {
        onboarding.show(at: .welcome, permissionLost: Settings.shared.didSetUp)
    }

    @objc private func showPermissionStep() {
        onboarding.show(at: .permission, permissionLost: Settings.shared.didSetUp)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// 메뉴 막대 앱이라 주 메뉴는 보이지 않지만, 설정 도우미의 입력칸에서 편집 단축키와 ⌘W가 동작하도록 둔다.
    private func installMainMenu() {
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let main = NSMenu()
        main.addItem(withTitle: "편집", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }

    // MARK: OnboardingHost

    func reapplyKeyMapping() -> [KeyConflict] {
        remapper.apply()
        updateIcon()
        return remapper.conflicts
    }

    func highlightStatusItem() {
        guard let button = statusItem?.button else { return }
        for index in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + Double(index) * 0.25) { button.highlight(index % 2 == 0) }
        }
    }

    func onboardingVisibilityChanged() {
        schedulePermissionTimer()
    }
}

// pkill 등 종료 신호에도 정상 종료 경로를 타서 키 매핑을 되돌린다.
let signalSources = [SIGTERM, SIGINT, SIGHUP].map { signalNumber -> DispatchSourceSignal in
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { NSApp.terminate(nil) }
    source.resume()
    return source
}

// 디버그(--simulate-untrusted): kill -USR1 <pid> 로 권한 허용·해제를 흉내 낸다.
let simulationSource: DispatchSourceSignal? = Accessibility.simulated == nil ? nil : {
    signal(SIGUSR1, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    source.setEventHandler { Accessibility.simulated?.toggle() }
    source.resume()
    return source
}()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
