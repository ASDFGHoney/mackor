import Combine
import MackorCore
import SwiftUI

struct OnboardingView: View {
    static let size = CGSize(width: 580, height: 570)

    @ObservedObject var controller: OnboardingController

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(current: controller.flow.step)
                .padding(.top, 34)
            Group {
                switch controller.flow.step {
                case .welcome: WelcomeStep(controller: controller)
                case .permission: PermissionStep(controller: controller)
                case .tryIt: TryStep(controller: controller)
                case .done: DoneStep(controller: controller)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(controller.flow.step)
            .transition(.opacity)
            Divider()
            Footer(controller: controller)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // 제목 막대는 투명하게 겹쳐 두고 그 자리까지 쓴다.
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: controller.flow.step)
    }
}

extension OnboardingStep {
    var title: String {
        switch self {
        case .welcome: "소개"
        case .permission: "권한"
        case .tryIt: "써 보기"
        case .done: "완료"
        }
    }
}

// MARK: - 틀

private struct StepIndicator: View {
    var current: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                if step != .welcome {
                    Capsule()
                        .fill(step <= current ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: 26, height: 2)
                }
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(step <= current ? Color.accentColor : Color.primary.opacity(0.1))
                        if step < current {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        } else {
                            Text("\(step.rawValue + 1)").font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(step <= current ? Color.white : Color.secondary)
                    .frame(width: 18, height: 18)
                    Text(step.title)
                        .font(.system(size: 12, weight: step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? Color.primary : Color.secondary)
                }
            }
        }
    }
}

private struct Footer: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        HStack {
            if controller.flow.canGoBack {
                Button("이전", action: controller.back)
            }
            Spacer()
            primary
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder private var primary: some View {
        let flow = controller.flow
        switch flow.step {
        case .welcome:
            Button("시작하기", action: controller.next).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        case .permission where flow.trusted:
            Button("다음", action: controller.next).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        case .permission:
            Button(flow.requestedAt == nil ? "접근성 권한 허용" : "시스템 설정 다시 열기", action: controller.requestPermission)
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        case .tryIt:
            // Return은 연습 입력칸이 쓰므로 기본 버튼으로 두지 않는다.
            Button("다음", action: controller.next).buttonStyle(.borderedProminent)
        case .done:
            Button("완료", action: controller.next).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - 1. 소개

private struct WelcomeStep: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        VStack(spacing: 0) {
            AppGlyph(size: 76)
                .padding(.top, 24)
            Text("mackor")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 14)
            Text("Caps Lock으로 한/영을 바로 바꾸고, 전환 직후 친 글자도 씹히지 않게 합니다.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 18) {
                InfoRow(symbol: "hand.raised.fill", color: .blue, title: "접근성 권한이 필요한 이유",
                        text: "Caps Lock을 누르는 순간 전환하고, 전환이 끝날 때까지 뒤따르는 키를 잠깐 붙잡았다가 순서대로 보내려면 키 입력을 받아야 합니다. macOS는 이런 앱에 접근성 권한을 요구합니다. 처음 한 번만 허용하면 됩니다.")
                InfoRow(symbol: "lock.fill", color: .green, title: "키 내용은 남기지 않습니다",
                        text: "입력한 내용을 저장하거나 기록하지 않습니다. 한/영을 전환하는 동안(보통 0.1초 안팎)만 메모리에서 보류합니다.")
                InfoRow(symbol: "capslock.fill", color: .orange, title: "Caps Lock은 한/영 키가 됩니다",
                        text: "mackor가 켜져 있는 동안 Caps Lock은 대문자 고정 대신 한/영 전환에만 쓰입니다. 대문자는 Shift로 입력하세요. Caps Lock은 한국어 자판에서 ‘한/A’라고 적힌 키입니다. mackor를 종료하면 원래대로 돌아옵니다.")
            }
            .padding(.top, 30)
        }
    }
}

// MARK: - 2. 권한

private struct PermissionStep: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        let flow = controller.flow
        VStack(alignment: .leading, spacing: 0) {
            Text(flow.trusted ? "접근성 권한이 허용되었습니다" : flow.permissionLost ? "접근성 권한이 꺼져 있습니다" : "접근성 권한을 허용해 주세요")
                .font(.system(size: 22, weight: .bold))
            Text(flow.trusted ? "이제 Caps Lock으로 한/영을 바꿀 수 있습니다. 다음 단계에서 써 보세요."
                 : flow.permissionLost ? "권한이 없으면 Caps Lock이 원래대로 돌아갑니다. 목록에서 mackor를 다시 켜 주세요."
                 : "시스템 설정에서 mackor를 켜기만 하면 됩니다. 허용되면 자동으로 다음 단계로 넘어갑니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            SettingsIllustration(granted: flow.trusted)
                .padding(.top, 18)
            if !flow.trusted {
                VStack(alignment: .leading, spacing: 7) {
                    NumberedRow(number: 1, text: "아래 버튼을 누르면 시스템 설정의 **손쉬운 사용** 목록이 열립니다.")
                    NumberedRow(number: 2, text: "목록에서 **mackor**를 켭니다. 암호나 Touch ID를 물으면 확인합니다.")
                    NumberedRow(number: 3, text: "켜는 즉시 이 창이 알아채고 다음 단계로 넘어갑니다.")
                }
                .padding(.top, 16)
            }
            StatusRow(trusted: flow.trusted, waiting: flow.requestedAt != nil)
                .padding(.top, 16)
            if !flow.trusted {
                Troubleshooting(controller: controller)
                    .padding(.top, 12)
            }
        }
    }
}

private struct StatusRow: View {
    var trusted: Bool
    var waiting: Bool

    var body: some View {
        HStack(spacing: 8) {
            if trusted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("허용됨").fontWeight(.medium)
            } else if waiting {
                ProgressView().controlSize(.small)
                Text("허용을 기다리는 중…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                Text("아직 허용되지 않았습니다").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .frame(height: 18)
    }
}

/// 토글은 켜져 있는데 앱은 허용되지 않은 경우(서명이 바뀌어 목록의 항목이 이전 앱을 가리킬 때).
private struct Troubleshooting: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        let signatureChanged = controller.hint == .signatureChanged
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { controller.showsTroubleshooting.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(controller.showsTroubleshooting ? 90 : 0))
                    Text(signatureChanged ? "⚠︎ 앱 서명이 바뀌어 다시 허용해야 합니다" : "목록에서 이미 켜져 있는데 넘어가지 않나요?")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(signatureChanged ? Color.orange : Color.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if controller.showsTroubleshooting {
                VStack(alignment: .leading, spacing: 7) {
                    Text(signatureChanged
                         ? "이전에 허용한 mackor와 앱 서명이 달라져, 목록의 항목이 이전 앱을 가리키고 있습니다."
                         : "앱이 업데이트되며 서명이 바뀌면 목록의 항목이 이전 앱을 가리켜, 켜져 있어도 허용되지 않습니다.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NumberedRow(number: 1, text: "목록에서 **mackor**를 선택하고 **−** 버튼으로 지웁니다.")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        NumberedRow(number: 2, text: "**목록에 다시 추가**를 누르고 새로 생긴 mackor를 켭니다.")
                        Spacer(minLength: 8)
                        Button("목록에 다시 추가", action: controller.requestPermission).controlSize(.small)
                    }
                    NumberedRow(number: 3, text: "목록에 나타나지 않으면 **+** 버튼으로 응용 프로그램 폴더의 mackor를 추가합니다.")
                }
                .font(.system(size: 12))
                .padding(.top, 8)
                .padding(.leading, 2)
            }
        }
    }
}

/// 시스템 설정의 손쉬운 사용 목록을 흉내 낸 그림. 무엇을 켜야 하는지 토글이 켜졌다 꺼졌다 하며 보여 준다.
private struct SettingsIllustration: View {
    var granted: Bool
    @State private var blink = false
    private let timer = Timer.publish(every: 1.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Text("개인정보 보호 및 보안").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                Text("손쉬운 사용").fontWeight(.semibold)
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.12)).frame(width: 22, height: 22)
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.12)).frame(width: 86, height: 9)
                Spacer()
                FakeSwitch(isOn: true)
            }
            .opacity(0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider().padding(.leading, 46)
            HStack(spacing: 10) {
                AppGlyph(size: 22)
                Text("mackor").font(.system(size: 13, weight: .medium))
                Spacer()
                if !granted {
                    HStack(spacing: 4) {
                        Text("여기를 켜세요")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
                FakeSwitch(isOn: granted || blink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(granted ? Color.clear : Color.accentColor.opacity(0.08))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onReceive(timer) { _ in
            guard !granted else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { blink.toggle() }
        }
    }
}

private struct FakeSwitch: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.15))
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1, y: 0.5).padding(2)
            }
    }
}

// MARK: - 3. 써 보기

private struct TryStep: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("한/영 전환을 써 보세요")
                .font(.system(size: 22, weight: .bold))
            Text("아래 칸에 입력하다가 Caps Lock으로 한/영을 바꿔 보세요. 빠르게 쳐도 글자가 씹히지 않습니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Label("mackor가 켜져 있는 동안 Caps Lock은 한/영 전환에만 쓰입니다. 대문자는 Shift로 입력하세요.", systemImage: "capslock")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            ForEach(controller.conflicts, id: \.self) { conflict in
                Warning(text: "\(conflict.keyboard): \(conflict.problem). \(conflict.remedy).")
                    .padding(.top, 6)
            }

            Text("연습").font(.headline).padding(.top, 22)
            PracticeField(placeholder: "Caps Lock으로 한/영을 바꿔 보세요")
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5))
                .padding(.top, 8)
            HStack(spacing: 8) {
                InputSourceBadge(source: controller.inputSource)
                Spacer()
                if controller.sawSwitch {
                    Label("전환을 확인했습니다", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .font(.system(size: 13))
            .padding(.top, 10)
            .animation(.easeInOut(duration: 0.15), value: controller.inputSource)
            .animation(.easeInOut(duration: 0.2), value: controller.sawSwitch)

            if controller.shortcutMissing {
                Warning(text: "전환 단축키가 꺼져 있습니다. 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스에서 ‘이전 입력 소스 선택’을 켜 주세요.")
                    .padding(.top, 12)
            }
            if controller.singleSource {
                Warning(text: "켜진 입력 소스가 하나뿐입니다. 시스템 설정 › 키보드 › 텍스트 입력 › 입력 소스 편집에서 ‘한국어 › 두벌식’을 추가해 주세요.")
                    .padding(.top, 12)
            }
        }
    }
}

/// 연습 입력칸. 이벤트 탭이 이 앱의 메인 스레드에서 돌기 때문에, 이 칸에 입력할 때는 mackor 자신이 맨 앞 앱이 된다.
/// 키마다 SwiftUI 화면을 다시 그리면 탭 처리가 늦어지므로 내용을 SwiftUI 상태로 묶지 않은 AppKit 입력칸을 쓴다.
private struct PracticeField: NSViewRepresentable {
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 18)
        // 테두리는 SwiftUI 쪽에서 그린다(둥근 테두리 칸은 높이가 고정이라 큰 글꼴이 잘린다).
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        // 창이 뜬 뒤에 바로 입력할 수 있도록 커서를 둔다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderString = placeholder
    }
}

private struct InputSourceBadge: View {
    var source: InputSourceInfo

    var body: some View {
        HStack(spacing: 8) {
            Text(source.isKorean ? "한" : "A")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(source.isKorean ? Color.white : Color.primary)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(source.isKorean ? Color.accentColor : Color.primary.opacity(0.12)))
            Text("현재 입력 소스").foregroundStyle(.secondary)
            Text(source.name).fontWeight(.medium)
        }
    }
}

// MARK: - 4. 완료

private struct DoneStep: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white, .green)
                .padding(.top, 4)
            Text("준비가 끝났습니다")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 12)
            Text("이제 어느 앱에서든 Caps Lock으로 한/영을 바꾸세요.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            MenuBarIllustration()
                .padding(.top, 26)
            Text("메뉴 막대 오른쪽 위의 키보드 아이콘에서 자동 실행을 바꾸고, 이 설정 도우미를 다시 열 수 있습니다. 아이콘이 가려져 보이지 않으면 mackor를 한 번 더 실행하세요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 34)

            LoginItemRow(controller: controller)
                .padding(.top, 24)
        }
    }
}

private struct LoginItemRow: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        let state = controller.loginItem
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "power.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(state == .unavailable ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("로그인 시 자동 실행").fontWeight(.medium)
                Group {
                    switch state {
                    case .enabled: Text("Mac에 로그인하면 mackor가 자동으로 켜집니다.")
                    case .disabled: Text("꺼 두면 Mac을 켤 때마다 mackor를 직접 실행해야 합니다.")
                    case .requiresApproval: Text("시스템 설정 › 일반 › 로그인 항목에서 허용해야 합니다.")
                    case .unavailable: Text("개발 실행 중에는 쓰지 않습니다. .app으로 실행할 때만 등록합니다.")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if state == .requiresApproval {
                Button("로그인 항목 열기", action: controller.openLoginItemSettings).controlSize(.small)
            }
            Toggle("로그인 시 자동 실행", isOn: Binding(get: { state == .enabled || state == .requiresApproval },
                                                    set: controller.setLoginItem))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(state == .unavailable)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// 메뉴 막대 오른쪽을 흉내 내 mackor 아이콘 위치를 가리킨다.
private struct MenuBarIllustration: View {
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Image(systemName: "keyboard")
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor.opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                .overlay(alignment: .top) {
                    VStack(spacing: 1) {
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 8))
                        Text("mackor").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .fixedSize()
                    .offset(y: 28)
                }
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Image(systemName: "switch.2")
            Text(Date(), style: .time)
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - 조각

/// 메뉴 막대 아이콘과 같은 키보드 모양의 앱 표시.
private struct AppGlyph: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.55, blue: 1.0), Color(red: 0.2, green: 0.34, blue: 0.92)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "keyboard")
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(.white))
    }
}

private struct InfoRow: View {
    var symbol: String
    var color: Color
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NumberedRow: View {
    var number: Int
    var text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Warning: View {
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.system(size: 12))
    }
}
