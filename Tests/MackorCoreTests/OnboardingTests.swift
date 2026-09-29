import Testing
@testable import MackorCore

@Suite("설정 도우미 흐름")
struct OnboardingTests {
    @Test("권한이 없을 때만 실행하자마자 띄운다")
    func launchStep() {
        #expect(OnboardingFlow.launchStep(trusted: false, didSetUp: false) == .welcome)
        #expect(OnboardingFlow.launchStep(trusted: false, didSetUp: true) == .permission, "설정을 마친 적이 있으면 소개는 건너뛴다")
        #expect(OnboardingFlow.launchStep(trusted: true, didSetUp: false) == nil, "권한을 유지한 채 업데이트한 기존 사용자")
        #expect(OnboardingFlow.launchStep(trusted: true, didSetUp: true) == nil)
    }

    @Test("처음 사용자: 소개 → 권한 → (허용되면 자동으로) 써 보기 → 완료")
    func firstRun() {
        var flow = OnboardingFlow(start: .welcome, trusted: false)
        flow.next()
        #expect(flow.step == .permission)
        #expect(!flow.canGoNext, "허용 전에는 넘어갈 수 없다")
        flow.next()
        #expect(flow.step == .permission)

        flow.requestPermission(now: 10)
        flow.trustChanged(true)
        #expect(flow.step == .tryIt && flow.requestedAt == nil)
        flow.next()
        #expect(flow.step == .done && !flow.isFinished)
        flow.next()
        #expect(flow.isFinished)
    }

    @Test("이미 허용돼 있으면 소개 다음에 권한 단계를 건너뛴다")
    func skipsPermissionWhenTrusted() {
        var flow = OnboardingFlow(start: .welcome, trusted: true)
        flow.next()
        #expect(flow.step == .tryIt)
        flow.back()
        #expect(flow.step == .permission && flow.canGoNext, "되돌아가면 허용됨 상태를 보여 주고 바로 넘어가지 않는다")
    }

    @Test("권한이 필요한 단계로 시작해도 권한이 없으면 권한 단계부터")
    func normalizesStart() {
        #expect(OnboardingFlow(start: .done, trusted: false).step == .permission)
        #expect(OnboardingFlow(start: .tryIt, trusted: true).step == .tryIt)
        #expect(!OnboardingFlow(start: .permission, trusted: true, permissionLost: true).permissionLost)
    }

    @Test("써 보는 중에 권한이 꺼지면 권한 단계로 돌아가고, 다시 켜면 이어서 진행한다")
    func revokedDuringTry() {
        var flow = OnboardingFlow(start: .tryIt, trusted: true)
        flow.trustChanged(false)
        #expect(flow.step == .permission && flow.permissionLost)
        flow.trustChanged(true)
        #expect(flow.step == .tryIt && !flow.permissionLost)
    }

    @Test("소개를 읽는 중에 권한이 바뀌어도 단계는 그대로")
    func welcomeStays() {
        var flow = OnboardingFlow(start: .welcome, trusted: false)
        flow.trustChanged(true)
        #expect(flow.step == .welcome)
        flow.trustChanged(false)
        #expect(flow.step == .welcome)
    }

    @Test("같은 상태가 반복해서 들어와도 변화로 보지 않는다")
    func repeatedTrustIsNoop() {
        var flow = OnboardingFlow(start: .permission, trusted: false)
        flow.requestPermission(now: 1)
        flow.trustChanged(false)
        #expect(flow.step == .permission && flow.requestedAt == 1 && !flow.permissionLost)
    }

    @Test("도움말: 허용을 오래 기다리면 낡은 항목일 수 있다고 안내한다")
    func slowGrantHint() {
        var flow = OnboardingFlow(start: .permission, trusted: false)
        #expect(flow.hint(now: 100, lastTrustedRequirement: nil, currentRequirement: "dr") == .none, "누르기 전에는 안내하지 않는다")
        flow.requestPermission(now: 100)
        flow.requestPermission(now: 105)
        #expect(flow.hint(now: 111, lastTrustedRequirement: nil, currentRequirement: "dr") == .none)
        #expect(flow.hint(now: 100 + OnboardingFlow.slowGrantDelay, lastTrustedRequirement: nil, currentRequirement: "dr") == .slowGrant,
                "처음 누른 시각부터 잰다")
        flow.trustChanged(true)
        #expect(flow.hint(now: 1000, lastTrustedRequirement: nil, currentRequirement: "dr") == .none)
    }

    @Test("도움말: 예전에 허용한 서명과 다르면 바로 안내한다")
    func signatureChangedHint() {
        let flow = OnboardingFlow(start: .permission, trusted: false, permissionLost: true)
        #expect(flow.hint(now: 0, lastTrustedRequirement: "old", currentRequirement: "new") == .signatureChanged)
        #expect(flow.hint(now: 0, lastTrustedRequirement: "same", currentRequirement: "same") == .none, "사용자가 직접 끈 경우")
        #expect(flow.hint(now: 0, lastTrustedRequirement: "old", currentRequirement: nil) == .none, "서명을 읽지 못하면 추측하지 않는다")
        let trusted = OnboardingFlow(start: .permission, trusted: true)
        #expect(trusted.hint(now: 0, lastTrustedRequirement: "old", currentRequirement: "new") == .none)
    }
}

@Suite("권한 변화 감지")
struct TrustWatchTests {
    @Test("실행 직후 상태는 변화가 아니다")
    func initialState() {
        var watch = TrustWatch()
        #expect(watch.update(false) == nil)
        var trusted = TrustWatch()
        #expect(trusted.update(true) == nil)
    }

    @Test("켜짐과 꺼짐을 한 번씩만 알린다")
    func edges() {
        var watch = TrustWatch()
        _ = watch.update(true)
        #expect(watch.update(true) == nil)
        #expect(watch.update(false) == .revoked)
        #expect(watch.update(false) == nil)
        #expect(watch.update(true) == .granted)
    }
}
