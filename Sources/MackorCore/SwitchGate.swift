import Foundation

/// 한/영 전환 중에 들어온 키를 잠시 붙잡아 두었다가, 전환이 끝나면 **이벤트 탭 콜백 안에서** 원래 순서대로 내보낸다.
///
/// macOS의 입력 소스 전환은 비동기라서, 전환 단축키를 보낸 뒤 약 20~130ms 동안 친 키는
/// 이전 입력 소스로 들어간다(빠르게 칠 때 "씹힘"의 원인). 입력 소스가 실제로 바뀔 때까지
/// 키를 보류하면 모든 키가 올바른 언어로 들어간다. 보류는 메모리에서만 한다.
///
/// 입력 소스 변경 알림은 전환 한 번에 여러 번 오거나 늦게 오기도 한다. 그래서 알림 횟수가 아니라
/// "전환을 시작할 때의 입력 소스에서 실제로 바뀌었는지"로 완료를 판단한다.
///
/// 앱이 받는 순서는 이벤트가 우리 탭을 떠나는 순서다. 완료는 탭 밖(알림, 재확인, 시간 초과)에서 알아채는데,
/// 그 자리에서 보류분을 HID 입구로 다시 보내면 이미 탭 앞까지 와 있던 키가 먼저 지나가 순서가 바뀐다
/// (20ms 간격으로 치면 hello → lhelo). 그래서 완료를 알아채면 `ready`로만 바꾸고, 다음 탭 콜백
/// (엔진이 보낸 배리어, 또는 그보다 먼저 온 키)이 받은 이벤트보다 먼저 보류분을 탭 자리에 넣게 한다.
public struct SwitchGate<Event> {
    private enum Item {
        case event(Event)
        case toggle
    }

    public enum Phase: Equatable, Sendable {
        /// 붙잡지 않는다. 키는 그대로 통과한다.
        case idle
        /// 전환 단축키를 보냈다. 입력 소스가 `from`에서 바뀌기를 기다리며 들어오는 키를 붙잡는다.
        case switching(from: String, since: TimeInterval)
        /// 전환이 끝났다(입력 소스가 `source`가 됐거나 시간 초과). 다음 탭 콜백이 보류분을 내보낸다.
        case ready(source: String)
    }

    /// 탭 콜백 한 번에 할 일. 엔진은 `release`를 탭 자리에 넣고, `switchAgain`이면 전환 단축키를 보내고,
    /// `passes`면 받은 이벤트를 돌려준다(이 순서를 지켜야 한다).
    public struct Step {
        /// 받은 이벤트보다 먼저, 이 순서대로 탭 자리에 넣을 보류 이벤트.
        public var release: [Event] = []
        /// `release`를 넣은 뒤 전환 단축키를 보내야 한다(새 전환, 또는 보류열에 있던 다음 전환 키).
        public var switchAgain = false
        /// 받은 이벤트를 그대로 통과시킨다. false면 삼킨다(붙잡았거나 전환 키·배리어).
        public var passes = true
    }

    /// 입력 소스가 이 시간 안에 바뀌지 않으면(단축키가 먹히지 않음 등) 전환이 끝난 것으로 보고 내보낸다.
    public static var timeout: TimeInterval { 0.3 }
    /// 보류할 수 있는 최대 항목 수(키와 전환 키). 넘으면 붙잡은 키를 순서대로 모두 내보내고 보류를 멈춘다.
    public static var capacity: Int { 256 }

    public private(set) var phase: Phase = .idle
    private var queue: [Item] = []

    public init() {}

    public var isIdle: Bool { phase == .idle }
    public var isSwitching: Bool { if case .switching = phase { true } else { false } }
    /// 전환이 끝나 보류분을 내보낼 탭 콜백을 기다리는 중.
    public var isReady: Bool { if case .ready = phase { true } else { false } }
    public var heldCount: Int { queue.count }

    // MARK: 탭 콜백(이벤트가 탭을 지나는 순서대로 부른다)

    /// 전환 키를 눌렀다(자동 반복 아님). 전환 키는 늘 삼킨다.
    /// 전환 중이면 순서를 지키기 위해 보류열에 넣고, 앞선 전환이 끝난 뒤 이어서 전환한다.
    /// `current`(입력 소스 조회)는 새 전환을 시작할 때만 평가한다.
    public mutating func toggle(now: TimeInterval, current: @autoclosure () -> String) -> Step {
        var step = drain(now: now)
        step.passes = false
        if isSwitching {
            guard queue.count >= Self.capacity else {
                queue.append(.toggle)
                return step
            }
            releaseAll(into: &step)
        }
        phase = .switching(from: current(), since: now)
        step.switchAgain = true
        return step
    }

    /// 전환 키가 아닌 키(keyDown, keyUp, flagsChanged). 전환 중이면 붙잡고, 전환이 끝나 있으면
    /// 보류분을 먼저 내보낸 뒤 통과시킨다. `event`(복사본)는 붙잡을 때만 평가한다.
    public mutating func receive(_ event: @autoclosure () -> Event, now: TimeInterval) -> Step {
        var step = drain(now: now)
        guard isSwitching else { return step }
        guard queue.count < Self.capacity else {
            // 자동화 도구의 폭주 등: 순서를 지켜 모두 내보내고, 받은 키는 그 뒤에 통과시킨다.
            releaseAll(into: &step)
            return step
        }
        queue.append(.event(event()))
        step.passes = false
        return step
    }

    /// 배리어(탭을 깨우려고 엔진이 보낸 이벤트)나 전환 키의 뗌·자동 반복이 왔다. 삼키되,
    /// 전환이 끝나 있으면 보류분을 내보낼 기회로 쓴다. 이미 내보냈거나 아직 전환 중이면 할 일이 없다.
    public mutating func wake(now: TimeInterval) -> Step {
        var step = drain(now: now)
        step.passes = false
        return step
    }

    // MARK: 탭 밖(알림, 재확인, 타이머)

    /// 입력 소스를 확인했다. 전환을 시작할 때와 다른 입력 소스가 됐으면 `ready`로 바꾸고 true: 탭을 깨워야 한다
    /// (보류분은 아직 내보내지 않는다). 이전 전환의 늦은 알림처럼 아직 바뀌지 않았거나, 조회에 실패한 빈 ID면 false.
    /// 전환을 시작할 때 조회에 실패해 `from`이 비어 있으면 바뀌었는지 알 수 없으므로 시간 초과로만 끝낸다.
    public mutating func sourceChanged(to current: String) -> Bool {
        guard case .switching(let from, _) = phase, !from.isEmpty, !current.isEmpty, current != from else { return false }
        phase = .ready(source: current)
        return true
    }

    /// 입력 소스가 바뀌지 않았어도 전환을 끝낸다(시간 초과, 단축키 없음, 입력 소스 하나뿐). true면 탭을 깨워야 한다.
    public mutating func expire(current: String) -> Bool {
        guard isSwitching else { return false }
        phase = .ready(source: current)
        return true
    }

    public func isTimedOut(now: TimeInterval) -> Bool {
        guard case .switching(_, let since) = phase else { return false }
        return now - since >= Self.timeout
    }

    /// 탭 콜백을 기다릴 수 없을 때(중지, 탭 꺼짐) 보류를 끝낸다. 붙잡은 키만 순서대로 돌려주고 대기 중이던 전환 키는 버린다.
    public mutating func flush() -> [Event] {
        var step = Step()
        releaseAll(into: &step)
        return step.release
    }

    // MARK: 내부

    /// 전환이 끝나 있으면 다음 전환 키 직전까지의 보류분을 꺼낸다. 전환 키를 만나면 그 자리에서 다음 전환을 시작한다.
    private mutating func drain(now: TimeInterval) -> Step {
        var step = Step()
        guard case .ready(let source) = phase else { return step }
        while !queue.isEmpty {
            switch queue.removeFirst() {
            case .event(let event):
                step.release.append(event)
            case .toggle:
                phase = .switching(from: source, since: now)
                step.switchAgain = true
                return step
            }
        }
        phase = .idle
        return step
    }

    /// 붙잡은 키를 순서대로 모두 꺼내고 보류를 멈춘다. 대기 중이던 전환 키는 버린다.
    private mutating func releaseAll(into step: inout Step) {
        for case .event(let event) in queue { step.release.append(event) }
        queue.removeAll()
        phase = .idle
    }
}
