import ServiceManagement

/// 로그인 시 자동 실행. .app 번들로 실행될 때만 다룬다(`Settings.isAppBundle`).
enum LoginItem {
    enum State { case unavailable, enabled, disabled, requiresApproval }

    static var state: State {
        guard Settings.shared.isAppBundle else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }

    static func set(_ enabled: Bool) {
        guard Settings.shared.isAppBundle else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log.error("로그인 항목 변경 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
