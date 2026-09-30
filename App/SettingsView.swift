import SwiftUI
import UIKit

struct SettingsView: View {
    /// 完全访问只影响键盘扩展联网（同步）；per-app 自签基线下主 App 无通道
    /// 感知该状态，故不展示授权提示。WebDAV 同步与日志均在键盘内完成。
    private var isOurKeyboardEnabled: Bool {
        let target = "art.anjing.quill.keyboard"
        if let keyboards = UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] {
            return keyboards.contains { $0.contains(target) }
        }
        return false
    }

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: isOurKeyboardEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundStyle(isOurKeyboardEnabled ? Color.green : Color.orange)
                            .frame(width: 24)
                        Text(isOurKeyboardEnabled ? "Quill 输入法已启用" : "Quill 输入法未启用")
                    }
                    if !isOurKeyboardEnabled {
                        Button {
                            openKeyboardSettings()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "keyboard")
                                    .font(.body)
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                Text("去系统设置中开启")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    LabeledContent("版本") {
                        Text(versionText)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("基于 RIME 输入法引擎：聪明的输入法懂我心意。")
                }
            }
            .formStyle(.grouped)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .padding(.top, 8)
            .navigationTitle("Quill 输入法")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    /// 逐级尝试直达键盘设置页，全部失败退回本 App 设置页（系统未公开直达 scheme）。
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
    SettingsView()
}
