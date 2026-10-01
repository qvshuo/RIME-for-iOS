import SwiftUI
import UIKit

struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isKeyboardEnabled = keyboardEnabled()
    private static func keyboardEnabled() -> Bool {
        let extensionBundleID = "art.anjing.rimeios.keyboard"
        if let keyboards = UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] {
            return keyboards.contains { $0.contains(extensionBundleID) }
        }
        return false
    }

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("RIME for iOS")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 20) {
                    Label {
                        Text(isKeyboardEnabled ? "输入法已启用" : "输入法未启用")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: isKeyboardEnabled ? "checkmark.circle.fill" : "keyboard")
                            .foregroundStyle(isKeyboardEnabled ? Color.green : Color.primary)
                    }
                    .font(.body)
                    if !isKeyboardEnabled {
                        Button("去系统设置中开启", systemImage: "arrow.up.forward") {
                            openKeyboardSettings()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 14) {
                    Text("关于").font(.subheadline).foregroundStyle(.secondary)
                    LabeledContent("版本", value: versionText)
                        .padding(20)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    Text("基于 RIME 输入法引擎：聪明的输入法懂我心意。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { isKeyboardEnabled = Self.keyboardEnabled() }
        }
    }

    /// 系统未公开直达键盘设置的 API；失败后退回应用设置。
    private func openKeyboardSettings() {
        let schemes = [
            "prefs:root=General&path=Keyboard/KEYBOARDS",
            "prefs:root=General&path=Keyboard",
            "App-Prefs:root=General&path=Keyboard/KEYBOARDS",
            "App-Prefs:root=General&path=Keyboard"
        ]
        var index = 0
        func tryNext() {
            guard index < schemes.count, let url = URL(string: schemes[index]) else {
                if let fallback = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(fallback)
                }
                return
            }
            index += 1
            UIApplication.shared.open(url) { opened in
                if !opened { tryNext() }
            }
        }
        tryNext()
    }
}

#Preview {
    SetupView()
}
