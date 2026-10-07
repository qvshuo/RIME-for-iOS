import SwiftUI
import UIKit

struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isKeyboardEnabled = keyboardEnabled()
    @State private var isTestingNetwork = false
    @State private var networkMessage: String?
    // 系统未提供完整的联网权限枚举；这里只保存连接确认结果，离线不等于拒绝授权。
    @AppStorage("networkAccessConfirmed") private var networkAccessConfirmed = false
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
                            .frame(width: 24)
                    }
                    .font(.body)
                    if !isKeyboardEnabled {
                        Button("去系统设置中开启", systemImage: "arrow.up.forward") {
                            openKeyboardSettings()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                    }
                    Divider()
                    Label {
                        Text(networkAccessConfirmed ? "已授予联网权限" : "未授予联网权限")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: networkAccessConfirmed ? "checkmark.circle.fill" : "network")
                            .foregroundStyle(networkAccessConfirmed ? Color.green : Color.primary)
                            .frame(width: 24)
                    }
                    .font(.body)
                    .accessibilityIdentifier("network-access-status")
                    if !networkAccessConfirmed {
                        Button("去系统设置中开启", systemImage: "arrow.up.forward") {
                            openAppSettings()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                        .disabled(isTestingNetwork)
                        .accessibilityIdentifier("enable-network-access")
                    }
                    if let networkMessage {
                        Text(networkMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                isKeyboardEnabled = Self.keyboardEnabled()
                Task { await checkNetworkAccess() }
            }
        }
    }

    @MainActor
    private func checkNetworkAccess() async {
        guard !isTestingNetwork else { return }
        isTestingNetwork = true
        networkMessage = nil
        defer { isTestingNetwork = false }
        // 前台应用请求公开连通性页面，让系统有机会展示其网络授权提示。
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let url = URL(string: "https://www.apple.com/library/test/success.html")!
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  String(decoding: data, as: UTF8.self).contains("<TITLE>Success</TITLE>") else {
                throw URLError(.badServerResponse)
            }
            networkAccessConfirmed = true
        } catch {
            networkAccessConfirmed = false
            networkMessage = "无法联网，请检查系统中的无线局域网／蜂窝数据权限和网络连接后重试。"
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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
