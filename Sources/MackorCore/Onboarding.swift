import Foundation

/// 설정 도우미의 단계. 권한은 설명(소개) 뒤에, 사용자가 버튼을 눌렀을 때 요청한다.
public enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case welcome, permission, tryIt, done

    /// 접근성 권한이 있어야 의미가 있는 단계(권한 없이는 한/영 키가 동작하지 않는다).
    public var needsTrust: Bool { self >= .tryIt }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 설정 도우미의 흐름. 권한 단계에서 허용되면 자동으로 다음 단계로 넘어가고,
/// 권한이 필요한 단계에서 권한이 꺼지면 권한 단계로 돌아간다.
public struct OnboardingFlow: Equatable, Sendable {
    /// "허용"을 누르고 이만큼 지나도 허용되지 않으면, 토글은 켜져 있는데 항목이 낡은 경우일 수 있다고 안내한다.
    public static var slowGrantDelay: TimeInterval { 12 }

    public private(set) var step: OnboardingStep
    public private(set) var trusted: Bool
    /// 설정을 마친 뒤 권한이 없어진 상태(실행 중 꺼짐, 꺼진 채 실행). 문구를 "꺼져 있습니다"로 바꾼다.
    public private(set) var permissionLost: Bool
    /// "접근성 권한 허용"을 처음 누른 시각. nil이면 아직 누르지 않았다.
    public private(set) var requestedAt: TimeInterval?
    public private(set) var isFinished = false

    public init(start: OnboardingStep, trusted: Bool, permissionLost: Bool = false) {
        step = start.needsTrust && !trusted ? .permission : start
        self.trusted = trusted
        self.permissionLost = permissionLost && !trusted
    }

    /// 실행할 때 띄울 단계. 권한이 있으면 띄우지 않는다(권한을 유지한 채 업데이트한 기존 사용자 포함).
    /// 설정을 마친 적이 있으면 소개는 건너뛰고 권한 단계로 바로 안내한다.
    public static func launchStep(trusted: Bool, didSetUp: Bool) -> OnboardingStep? {
        guard !trusted else { return nil }
        return didSetUp ? .permission : .welcome
    }

    public var canGoBack: Bool { step != .welcome }
    /// 권한 단계는 허용되어야 넘어갈 수 있다(허용되면 자동으로 넘어간다).
    public var canGoNext: Bool { step != .permission || trusted }

    public mutating func next() {
        switch step {
        case .welcome: step = trusted ? .tryIt : .permission
        case .permission: if trusted { step = .tryIt }
        case .tryIt: step = .done
        case .done: isFinished = true
        }
    }

    public mutating func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public mutating func requestPermission(now: TimeInterval) {
        if requestedAt == nil { requestedAt = now }
    }

    public mutating func trustChanged(_ trusted: Bool) {
        guard trusted != self.trusted else { return }
        self.trusted = trusted
        if trusted {
            requestedAt = nil
            permissionLost = false
            if step == .permission { step = .tryIt }
        } else {
            permissionLost = true
            if step.needsTrust { step = .permission }
        }
    }

    /// 권한 단계에서 보여 줄 도움말.
    /// - Parameters:
    ///   - lastTrustedRequirement: 마지막으로 허용되었을 때의 코드 서명 요구 사항(designated requirement).
    ///   - currentRequirement: 지금 실행 중인 앱의 요구 사항. 접근성 권한(TCC)은 이것에 묶인다.
    public func hint(now: TimeInterval, lastTrustedRequirement: String?, currentRequirement: String?) -> PermissionHint {
        guard !trusted else { return .none }
        if let lastTrustedRequirement, let currentRequirement, lastTrustedRequirement != currentRequirement {
            return .signatureChanged
        }
        if let requestedAt, now - requestedAt >= Self.slowGrantDelay { return .slowGrant }
        return .none
    }
}

public enum PermissionHint: Equatable, Sendable {
    case none
    /// 허용을 오래 기다리는 중: 목록의 토글이 이미 켜져 있다면 항목이 낡았을 수 있다.
    case slowGrant
    /// 예전에 허용한 앱과 서명이 다르다: 목록의 항목이 이전 서명을 가리켜 켜져 있어도 허용되지 않는다.
    case signatureChanged
}

/// 권한 변화 감지. 실행 직후의 첫 상태는 변화로 보지 않는다(처음부터 없던 권한은 "꺼짐"이 아니다).
public struct TrustWatch: Sendable {
    public enum Change: Equatable, Sendable { case granted, revoked }

    private var last: Bool?

    public init() {}

    public mutating func update(_ trusted: Bool) -> Change? {
        defer { last = trusted }
        guard let last, last != trusted else { return nil }
        return trusted ? .granted : .revoked
    }
}
