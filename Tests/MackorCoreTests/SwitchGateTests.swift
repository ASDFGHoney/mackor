import Testing
@testable import MackorCore

private typealias Gate = SwitchGate<String>
private let korean = "com.apple.inputmethod.Korean.2SetKorean"
private let abc = "com.apple.keylayout.ABC"

/// 탭 콜백 한 번을 흉내 낸다: 보류분을 먼저 내보내고, 통과면 받은 키를 그 뒤에 붙인다.
private func deliver(_ step: Gate.Step, _ event: String?, into output: inout [String]) {
    output += step.release
    if step.passes, let event { output.append(event) }
}

@Suite("전환 중 입력 보류")
struct SwitchGateTests {
    @Test("평소에는 아무것도 붙잡지 않고 복사본도 만들지 않는다")
    func idlePassesThrough() {
        var gate = Gate()
        var copied = false
        let step = gate.receive({ copied = true; return "a" }(), now: 0)
        #expect(step.passes && step.release.isEmpty && !step.switchAgain)
        #expect(!copied && gate.isIdle)
    }

    @Test("전환 중 친 키는 입력 소스가 바뀐 뒤 다음 탭 콜백에서 순서대로 나간다")
    func holdsUntilSwitched() {
        var gate = Gate()
        let start = gate.toggle(now: 0, current: korean)
        #expect(start.switchAgain && !start.passes && start.release.isEmpty)
        for key in ["d", "u", "d"] {
            let held = gate.receive(key, now: 0.01)
            #expect(!held.passes)
        }
        let done = gate.sourceChanged(to: abc)
        #expect(done, "완료를 알아채면 탭을 깨운다")
        #expect(gate.isReady && gate.heldCount == 3, "탭 밖에서는 내보내지 않는다")
        let barrier = gate.wake(now: 0.021)
        #expect(barrier.release == ["d", "u", "d"] && !barrier.switchAgain && !barrier.passes)
        #expect(gate.isIdle)
        let after = gate.receive("x", now: 0.03)
        #expect(after.passes && after.release.isEmpty, "전환이 끝나면 다시 그대로 통과")
    }

    @Test("전환이 끝난 순간 이미 탭 앞에 와 있던 키는 보류분 뒤에 나간다(20ms 간격 hello → lhelo 회귀)")
    func keyBeforeBarrierKeepsOrder() {
        // t:dkssud w20 f79 t:h w20 t:e w20 t:l …: 완료를 알아챈 순간 l은 이미 탭 앞에 와 있어 배리어보다 먼저 콜백에 들어온다.
        var gate = Gate()
        var output: [String] = []
        deliver(gate.toggle(now: 0, current: korean), nil, into: &output)
        for key in ["h↓", "h↑"] { deliver(gate.receive(key, now: 0.001), key, into: &output) }
        for key in ["e↓", "e↑"] { deliver(gate.receive(key, now: 0.02), key, into: &output) }
        let done = gate.sourceChanged(to: abc)
        #expect(done)
        for key in ["l↓", "l↑"] { deliver(gate.receive(key, now: 0.04), key, into: &output) }
        let lateBarrier = gate.wake(now: 0.041)
        #expect(lateBarrier.release.isEmpty && !lateBarrier.switchAgain, "뒤늦게 온 배리어는 할 일이 없다")
        #expect(output == ["h↓", "h↑", "e↓", "e↑", "l↓", "l↑"])
        #expect(gate.isIdle)
    }

    @Test("아직 바뀌지 않았다는 늦은 알림과 빈 입력 소스 ID로는 끝내지 않는다")
    func staleNotificationIgnored() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: abc)
        _ = gate.receive("g", now: 0.001)
        let stale = gate.sourceChanged(to: abc)
        let empty = gate.sourceChanged(to: "")
        #expect(!stale && !empty && gate.isSwitching && gate.heldCount == 1)
        let early = gate.wake(now: 0.002)
        #expect(early.release.isEmpty && !early.passes, "전환 중에 온 배리어는 삼키기만 한다")
        let real = gate.sourceChanged(to: korean)
        let barrier = gate.wake(now: 0.03)
        #expect(real && barrier.release == ["g"])
    }

    @Test("전환 중에 다시 누른 전환 키는 앞선 보류분을 내보낸 뒤 이어서 처리한다")
    func queuedToggle() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("d", now: 0.001)
        let second = gate.toggle(now: 0.01, current: korean)
        #expect(!second.switchAgain && !second.passes, "지금 바로 보내면 순서가 섞인다")
        _ = gate.receive("g", now: 0.011)
        _ = gate.receive("k", now: 0.012)

        _ = gate.sourceChanged(to: abc)
        let first = gate.wake(now: 0.03)
        #expect(first.release == ["d"] && first.switchAgain, "영문 d를 먼저 내보내고 다시 전환")
        #expect(gate.phase == .switching(from: abc, since: 0.03))

        let late = gate.sourceChanged(to: abc)
        #expect(!late, "첫 전환의 늦은 알림은 두 번째 전환을 끝내지 않는다")
        let done = gate.sourceChanged(to: korean)
        let last = gate.wake(now: 0.06)
        #expect(done && last.release == ["g", "k"] && !last.switchAgain)
        #expect(gate.isIdle)
    }

    @Test("전환이 끝났는데 배리어보다 먼저 온 전환 키는 보류분을 내보낸 뒤 새 전환을 시작한다")
    func toggleWhileReady() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("a", now: 0.001)
        _ = gate.sourceChanged(to: abc)
        let step = gate.toggle(now: 0.03, current: abc)
        #expect(step.release == ["a"] && step.switchAgain && !step.passes)
        #expect(gate.phase == .switching(from: abc, since: 0.03))
    }

    @Test("전환 키의 뗌이나 자동 반복도 끝난 전환의 보류분을 내보낼 기회가 된다")
    func toggleNoiseReleases() {
        var gate = Gate()
        let idle = gate.wake(now: 0)
        #expect(idle.release.isEmpty && !idle.passes && gate.isIdle, "평소에 온 뗌·배리어는 삼키기만 한다")
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("c", now: 0.001)
        let during = gate.wake(now: 0.002)
        #expect(during.release.isEmpty && gate.isSwitching, "전환 중인 뗌은 전환을 끝내지 않는다")
        _ = gate.sourceChanged(to: abc)
        let release = gate.wake(now: 0.03)
        #expect(release.release == ["c"] && gate.isIdle)
    }

    @Test("20번 연타해도 모든 키가 원래 순서로, 전환 키 한 번당 한 번씩 전환해 나간다")
    func rapidToggles() {
        var gate = Gate()
        var output: [String] = []
        var switches = 0
        var source = korean
        var now = 0.0
        for index in 0..<20 {
            if gate.toggle(now: now, current: source).switchAgain { switches += 1 }
            _ = gate.receive("k\(index)", now: now)
        }
        for _ in 0..<20 {
            now += 0.02
            // 늦은 알림이 섞여 와도 결과는 같아야 한다.
            let stale = gate.sourceChanged(to: source)
            source = source == korean ? abc : korean
            let done = gate.sourceChanged(to: source)
            #expect(!stale && done)
            let step = gate.wake(now: now)
            output += step.release
            if step.switchAgain { switches += 1 }
        }
        #expect(gate.isIdle, "전환 20번이면 보류열이 모두 비어야 한다")
        #expect(output == (0..<20).map { "k\($0)" })
        #expect(switches == 20, "전환 키 한 번당 전환 한 번")
    }

    @Test("입력 소스가 안 바뀌면 시간 초과로 끝내고 다음 탭 콜백에서 내보낸다")
    func timeout() {
        var gate = Gate()
        _ = gate.toggle(now: 1, current: korean)
        _ = gate.receive("a", now: 1)
        #expect(!gate.isTimedOut(now: 1.2))
        #expect(gate.isTimedOut(now: 1.3))
        let expired = gate.expire(current: korean)
        let barrier = gate.wake(now: 1.3)
        #expect(expired && barrier.release == ["a"])
        let again = gate.expire(current: korean)
        #expect(!again && !gate.isTimedOut(now: 2), "전환 중이 아니면 끝낼 것이 없다")
    }

    @Test("시간 초과 뒤에도 보류열의 전환 키는 차례대로 이어서 처리한다")
    func timeoutThenQueuedToggle() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("a", now: 0.01)
        _ = gate.toggle(now: 0.02, current: korean)
        _ = gate.receive("b", now: 0.03)
        _ = gate.expire(current: korean)
        let step = gate.wake(now: 0.3)
        #expect(step.release == ["a"] && step.switchAgain)
        #expect(gate.phase == .switching(from: korean, since: 0.3), "바뀌지 않은 입력 소스에서 다시 시작")
    }

    @Test("전환을 시작할 때 입력 소스 조회에 실패했으면(빈 ID) 알림으로 끝내지 않고 시간 초과로만 끝낸다")
    func unknownStartSource() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: "")
        _ = gate.receive("h", now: 0.001)
        let unchanged = gate.sourceChanged(to: korean)
        let changed = gate.sourceChanged(to: abc)
        #expect(!unchanged && !changed && gate.isSwitching, "어디서 시작했는지 모르면 바뀌었는지 알 수 없다")
        #expect(gate.wake(now: 0.006).release.isEmpty, "아직 바뀌지 않았을 수 있는 입력 소스로 내보내지 않는다")
        #expect(gate.isTimedOut(now: 0.3))
        let expired = gate.expire(current: abc)
        let barrier = gate.wake(now: 0.3)
        #expect(expired && barrier.release == ["h"] && gate.isIdle)
    }

    @Test("시간 초과 때 조회에 실패해 빈 ID에서 이어지는 연쇄 전환도 시간 초과로만 끝낸다")
    func unknownSourceAfterTimeout() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("a", now: 0.01)
        _ = gate.toggle(now: 0.02, current: korean)
        _ = gate.receive("b", now: 0.03)
        _ = gate.expire(current: "")
        let step = gate.wake(now: 0.3)
        #expect(step.release == ["a"] && step.switchAgain)
        #expect(gate.phase == .switching(from: "", since: 0.3))
        let early = gate.sourceChanged(to: korean)
        #expect(!early && gate.heldCount == 1, "바뀌지 않은 입력 소스를 완료로 보면 b가 이전 언어로 나간다")
    }

    @Test("우리가 시작하지 않은 전환 알림은 무시한다")
    func unrelatedNotification() {
        var gate = Gate()
        let changed = gate.sourceChanged(to: abc)
        let expired = gate.expire(current: abc)
        #expect(!changed && !expired && gate.isIdle)
    }

    @Test("보류 용량을 넘으면 붙잡은 키를 순서대로 모두 내보내고 보류를 멈춘다")
    func capacity() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("a", now: 0)
        _ = gate.toggle(now: 0, current: korean)
        for index in 0..<(Gate.capacity - 2) { _ = gate.receive("\(index)", now: 0) }
        #expect(gate.heldCount == Gate.capacity)
        let overflow = gate.receive("over", now: 0.01)
        #expect(overflow.release == ["a"] + (0..<(Gate.capacity - 2)).map { "\($0)" }, "대기 중이던 전환 키는 버린다")
        #expect(overflow.passes && !overflow.switchAgain && gate.isIdle, "넘친 키는 보류분 뒤에 통과")
    }

    @Test("보류 용량을 넘은 순간 누른 전환 키는 보류분을 내보낸 뒤 새 전환을 시작한다")
    func capacityToggle() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        for index in 0..<Gate.capacity { _ = gate.receive("\(index)", now: 0) }
        let overflow = gate.toggle(now: 0.01, current: abc)
        #expect(overflow.release.count == Gate.capacity && overflow.switchAgain && !overflow.passes)
        #expect(gate.phase == .switching(from: abc, since: 0.01) && gate.heldCount == 0)
    }

    @Test("중지하면 보류한 키만 순서대로 돌려주고 남은 전환 키는 버린다")
    func flush() {
        var gate = Gate()
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("a", now: 0)
        _ = gate.toggle(now: 0, current: korean)
        _ = gate.receive("b", now: 0)
        let flushed = gate.flush()
        #expect(flushed == ["a", "b"])
        #expect(gate.isIdle && gate.heldCount == 0)
    }
}

@Suite("이벤트 흐름 모형에서 순서 보존")
struct SwitchPipelineTests {
    @Test("어떤 순서로 도착하고 전환이 언제 끝나도 앱이 받는 순서와 언어는 친 그대로다", arguments: 0..<500)
    func ordered(seed: Int) {
        var pipeline = Pipeline(seed: UInt64(seed), options: .init())
        pipeline.run()
        #expect(pipeline.output == pipeline.keys, "seed \(seed)")
        #expect(pipeline.wrongLanguage.isEmpty, "seed \(seed)")
        #expect(pipeline.shortcuts == pipeline.toggles, "전환 키 한 번당 전환 한 번")
        #expect(pipeline.gate.isIdle)
    }

    @Test("시간 초과가 아무 때나 끼어도 나가는 순서는 친 그대로다", arguments: 0..<500)
    func orderedWithTimeouts(seed: Int) {
        var pipeline = Pipeline(seed: UInt64(seed) &+ 10_000, options: .init(timeouts: true))
        pipeline.run()
        #expect(pipeline.output == pipeline.keys, "seed \(seed)")
        #expect(pipeline.shortcuts == pipeline.toggles)
        #expect(pipeline.gate.isIdle)
    }

    @Test("배리어를 잃어 탭 밖에서 내보내도 키를 잃거나 겹치거나 멈추지 않는다", arguments: 0..<500)
    func lostBarrier(seed: Int) {
        var pipeline = Pipeline(seed: UInt64(seed) &+ 20_000, options: .init(timeouts: true, lostBarriers: true))
        pipeline.run()
        #expect(pipeline.output.sorted() == pipeline.keys.sorted(), "seed \(seed)")
        #expect(pipeline.gate.isIdle)
    }

    @Test("모형 점검: 탭 밖에서 HID 입구로 다시 보내면(예전 방식) 같은 모형에서 순서가 바뀐다")
    func oldRuleReorders() {
        var reordered = 0
        for seed in 0..<500 {
            var pipeline = Pipeline(seed: UInt64(seed), options: .init(releaseOutsideOnly: true))
            pipeline.run()
            #expect(pipeline.output.sorted() == pipeline.keys.sorted())
            if pipeline.output != pipeline.keys { reordered += 1 }
        }
        #expect(reordered > 0, "모형이 예전 버그를 재현하지 못하면 위 모형 테스트는 의미가 없다")
    }
}

/// 재현 가능한 난수(시드 고정).
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 이벤트 흐름 모형. 친 이벤트는 HID 줄 → 세션 줄 → 우리 탭 순서로 흐르고(각 줄은 FIFO), 탭이 엔진 규칙대로
/// 내보낸 순서가 앱이 받는 순서다. 줄 이동, 탭 처리, 시스템의 전환 반영, 메인 스레드의 완료 감지(늦은 알림 포함),
/// 시간 초과, 배리어 분실이 아무 순서로나 끼어든다. 배리어는 세션 입구로, 탭 밖 재전송은 HID 입구로 들어간다.
private struct Pipeline {
    struct Options {
        var timeouts = false
        var lostBarriers = false
        /// 예전 방식: 완료를 알아채면 곧바로 탭 밖에서 HID 입구로 다시 보낸다.
        var releaseOutsideOnly = false
    }

    enum Event {
        case key(String)
        case toggleDown
        case toggleUp
        case barrier
        case resent(String)
    }

    var gate = SwitchGate<String>()
    var rng: SplitMix64
    let options: Options
    var typed: [Event] = []
    var keys: [String] = []
    var toggles = 0
    /// 키마다 들어가야 할 입력 소스(앞선 전환 키 수로 정해진다).
    var expected: [String: String] = [:]

    var hidLine: [Event] = []
    var sessionLine: [Event] = []
    var system = korean
    var pendingSwitches = 0
    var lostBarriers = 0
    var shortcuts = 0
    var output: [String] = []
    var wrongLanguage: [String] = []
    var now = 0.0

    init(seed: UInt64, options: Options) {
        rng = SplitMix64(state: seed)
        self.options = options
        var source = korean
        var pendingUp = false
        for index in 0..<Int.random(in: 1...30, using: &rng) {
            if Int.random(in: 0..<4, using: &rng) == 0 {
                if pendingUp { typed.append(.toggleUp) }
                typed.append(.toggleDown)
                toggles += 1
                source = source == korean ? abc : korean
                // 절반은 곧바로 떼고, 절반은 다음 키를 친 뒤에 뗀다(한/영 키를 누른 채 다음 단어).
                pendingUp = Bool.random(using: &rng)
                if !pendingUp { typed.append(.toggleUp) }
            } else {
                let key = "k\(index)"
                typed.append(.key(key))
                keys.append(key)
                expected[key] = source
                if pendingUp { typed.append(.toggleUp); pendingUp = false }
            }
        }
        if pendingUp { typed.append(.toggleUp) }
        typed.reverse()
    }

    mutating func run() {
        var steps = 0
        while !typed.isEmpty || !hidLine.isEmpty || !sessionLine.isEmpty || !gate.isIdle || pendingSwitches > 0 || lostBarriers > 0 {
            steps += 1
            guard steps < 200_000 else { Issue.record("끝나지 않음"); return }
            now += 0.001
            switch Int.random(in: 0..<8, using: &rng) {
            case 0 where !typed.isEmpty:
                hidLine.append(typed.removeLast())
            case 1 where !hidLine.isEmpty:
                // HID 단계의 다른 앱 탭을 지나 세션 단계로.
                sessionLine.append(hidLine.removeFirst())
            case 2 where !sessionLine.isEmpty:
                tap(sessionLine.removeFirst())
            case 3 where pendingSwitches > 0:
                // 시스템이 전환 단축키를 반영했다.
                pendingSwitches -= 1
                system = system == korean ? abc : korean
            case 4:
                // 메인 스레드: 알림 또는 재확인. 아직 안 바뀐 늦은 알림도 여기에 해당한다.
                if gate.sourceChanged(to: system) { wakeTap() }
            case 5 where options.timeouts && Int.random(in: 0..<6, using: &rng) == 0:
                if gate.expire(current: system) { wakeTap() }
            case 6 where lostBarriers > 0:
                // 배리어 기한이 지났다: 탭 밖에서 내보낸다.
                lostBarriers -= 1
                if gate.isReady { releaseOutsideTap() }
            default:
                break
            }
        }
    }

    private mutating func wakeTap() {
        if options.releaseOutsideOnly {
            releaseOutsideTap()
        } else if options.lostBarriers, Int.random(in: 0..<3, using: &rng) == 0 {
            lostBarriers += 1
        } else {
            sessionLine.append(.barrier)
        }
    }

    private mutating func releaseOutsideTap() {
        let step = gate.wake(now: now)
        hidLine += step.release.map { .resent($0) }
        if step.switchAgain { beginSwitch() }
    }

    private mutating func tap(_ event: Event) {
        switch event {
        case .barrier, .toggleUp:
            apply(gate.wake(now: now), passing: nil)
        case .resent(let key):
            emit(key)
        case .toggleDown:
            apply(gate.toggle(now: now, current: system), passing: nil)
        case .key(let key):
            if gate.isIdle { emit(key) } else { apply(gate.receive(key, now: now), passing: key) }
        }
    }

    /// 엔진과 같은 순서: 보류분을 탭 자리에 넣고 → 전환 단축키 → 받은 키 통과.
    private mutating func apply(_ step: SwitchGate<String>.Step, passing key: String?) {
        #expect(!(step.passes && step.switchAgain), "새 전환을 시작하는 콜백은 받은 키를 통과시키지 않는다")
        for released in step.release { emit(released) }
        if step.switchAgain { beginSwitch() }
        if step.passes, let key { emit(key) }
    }

    private mutating func beginSwitch() {
        pendingSwitches += 1
        shortcuts += 1
    }

    private mutating func emit(_ key: String) {
        output.append(key)
        if expected[key] != system { wrongLanguage.append(key) }
    }
}
