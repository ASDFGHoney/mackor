// mackor 종단 간 검증 도구. scripts/e2e.sh 에서 쓴다.
//  창 모드(--window [--trace], Lab.app으로 open): 텍스트 뷰를 띄우고 내용을 state 파일에 계속 기록한다.
//  보내기 모드(기본, 터미널에서 실행 → 터미널의 접근성 권한 상속): 실험 창이 맨 앞일 때만 시스템 수준 키 이벤트를 보낸다.
// 단계: kNNN(누름+뗌) dNNN/uNNN(누름/뗌) fNNN(기능키 탭) FNNN/UNNN(기능키 누름/뗌) cNNN(⌃+키) t:문자열 wNNN(ms)
//       ready settle txt clear note src sel:ID
import AppKit
import Carbon

let labBundleID = "io.mackor.switchlab"
let workDirectory = ProcessInfo.processInfo.environment["MACKOR_E2E_DIR"] ?? NSTemporaryDirectory() + "mackor-e2e"
let statePath = workDirectory + "/state.txt"
let clearFlag = workDirectory + "/clear.flag"

func currentSource() -> String {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    return Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue() as String
}

// 진단 기록(창 모드 --trace): 실험 창이 키를 받은 순간 자기 입력 컨텍스트의 입력 소스, 입력된 글자,
// 입력 컨텍스트가 바뀐 순간을 trace.txt에 남긴다. mackor 로그(log stream)와 시각으로 맞춰 본다.
// (open으로 띄우는 창에는 환경 변수가 전달되지 않으므로 인자로 켠다.)
let tracePath = workDirectory + "/trace.txt"
let tracing = CommandLine.arguments.contains("--trace")
let traceClock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

func trace(_ line: String) {
    guard tracing else { return }
    let text = "\(traceClock.string(from: Date())) \(line)\n"
    if let handle = FileHandle(forWritingAtPath: tracePath) {
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try? handle.close()
    } else {
        try? text.write(toFile: tracePath, atomically: false, encoding: .utf8)
    }
}

final class TraceTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        trace("key \(event.keyCode) ctx=\(inputContext?.selectedKeyboardInputSource ?? "?")")
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        trace("insert \"\(string)\" ctx=\(inputContext?.selectedKeyboardInputSource ?? "?")")
        super.insertText(string, replacementRange: replacementRange)
    }
}

final class Window: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 560, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
    let textView = TraceTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 140))
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "mackor 전환 실험 — 키보드·마우스를 건드리지 마세요"
        window.contentView = textView
        textView.font = .systemFont(ofSize: 20)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            trace("ctx \(self?.textView.inputContext?.selectedKeyboardInputSource ?? "?")")
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { exit(0) }
    }

    func tick() {
        if FileManager.default.fileExists(atPath: clearFlag) {
            try? FileManager.default.removeItem(atPath: clearFlag)
            textView.inputContext?.discardMarkedText()
            textView.string = ""
        }
        let ready = NSApp.isActive && window.isKeyWindow && window.firstResponder === textView
        let state = "\(textView.hasMarkedText() ? 1 : 0)\t\(ready ? 1 : 0)\t\(textView.string)"
        try? state.write(toFile: statePath, atomically: true, encoding: .utf8)
    }
}

let qwerty: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
    "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "_": 49, "1": 18, "2": 19,
]
let eventSource = CGEventSource(stateID: .hidSystemState)

func wait(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }

// 입력 소스 변경 알림 관찰(보내기 모드). 마지막 전환 키를 보낸 시각부터 알림까지의 시간을 잰다.
var lastToggleAt = 0.0
var notedAt: Double?
let noteObserver = DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: nil
) { _ in notedAt = ProcessInfo.processInfo.systemUptime }
func now() -> Double { ProcessInfo.processInfo.systemUptime }

func ensureFront() {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == labBundleID else {
        print("ABORT: 실험 창이 맨 앞이 아닙니다(\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")). 다른 앱에 입력하지 않도록 중단합니다.")
        exit(3)
    }
}

func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
    ensureFront()
    let e = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down)!
    e.flags = flags
    e.post(tap: .cghidEventTap)
}

func runSteps(_ steps: [String]) {
    for step in steps {
        if step.hasPrefix("k"), let c = CGKeyCode(step.dropFirst()) { post(c, down: true); post(c, down: false) }
        // 기능키(F13~F20)는 하드웨어와 같이 SecondaryFn 플래그를 붙인다.
        else if step.hasPrefix("f"), let c = CGKeyCode(step.dropFirst()) {
            notedAt = nil; lastToggleAt = now()
            post(c, down: true, flags: .maskSecondaryFn); post(c, down: false, flags: .maskSecondaryFn)
        }
        // note: 전환 알림이 올 때까지(최대 500ms) 기다리고 경과 시간을 출력
        else if step == "note" {
            let deadline = lastToggleAt + 0.5
            while notedAt == nil && now() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001)) }
            print(notedAt.map { String(format: "note: %.1fms", ($0 - lastToggleAt) * 1000) } ?? "note: 시간 초과")
        }
        else if step.hasPrefix("F"), let c = CGKeyCode(step.dropFirst()) { post(c, down: true, flags: .maskSecondaryFn) }
        else if step.hasPrefix("U"), let c = CGKeyCode(step.dropFirst()) { post(c, down: false, flags: .maskSecondaryFn) }
        else if step.hasPrefix("d"), let c = CGKeyCode(step.dropFirst()) { post(c, down: true) }
        else if step.hasPrefix("u"), let c = CGKeyCode(step.dropFirst()) { post(c, down: false) }
        else if step.hasPrefix("t:") {
            for ch in step.dropFirst(2) {
                let code = qwerty[Character(ch.lowercased())]!
                let flags: CGEventFlags = ch.isUppercase ? .maskShift : []
                post(code, down: true, flags: flags); post(code, down: false, flags: flags)
            }
        }
        // cNNN: ⌃ 누른 채 키코드 NNN 탭
        else if step.hasPrefix("c"), let c = CGKeyCode(step.dropFirst()) {
            post(59, down: true, flags: .maskControl)
            post(c, down: true, flags: .maskControl); post(c, down: false, flags: .maskControl)
            post(59, down: false)
        }
        else if step.hasPrefix("w"), let ms = Double(step.dropFirst()) { wait(ms / 1000) }
        else if step == "src" { print("src:", currentSource()) }
        else if step == "txt" {
            wait(0.05)
            let raw = (try? String(contentsOfFile: statePath, encoding: .utf8)) ?? "?\t?\t?"
            let parts = raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            print("txt: \"\(parts.count > 2 ? String(parts[2]) : "")\" marked=\(parts.first == "1")")
        }
        // settle: 텍스트가 700ms 동안 바뀌지 않을 때까지 기다린다(최대 8초). 보류 중인 키가 모두 나온 뒤에 읽고 닫기 위해서.
        else if step == "settle" {
            var last = "", stableSince = Date()
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                let raw = (try? String(contentsOfFile: statePath, encoding: .utf8)) ?? ""
                if raw != last { last = raw; stableSince = Date() }
                if Date().timeIntervalSince(stableSince) > 0.7 { break }
                wait(0.02)
            }
        }
        // ready: 실험 창이 실제로 키 입력을 받을 준비가 될 때까지 기다린다(최대 3초).
        else if step == "ready" {
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                let raw = (try? String(contentsOfFile: statePath, encoding: .utf8)) ?? ""
                if raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).dropFirst().first == "1" { break }
                wait(0.02)
            }
            ensureFront()
            wait(0.1)
        }
        else if step == "clear" { FileManager.default.createFile(atPath: clearFlag, contents: nil); wait(0.1) }
        else if step.hasPrefix("sel:") {
            let id = String(step.dropFirst(4))
            let list = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
            print("select", id, list.first.map { TISSelectInputSource($0) } ?? -1)
        }
        else { print("알 수 없는 단계:", step) }
    }
}

if CommandLine.arguments.contains("--window") {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = Window()
    app.delegate = delegate
    app.run()
} else {
    runSteps(CommandLine.arguments.dropFirst().joined(separator: " ").split(separator: " ").map(String.init))
}
