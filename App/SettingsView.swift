import SwiftUI
import UIKit
import Security
import RimeEngine
import Sync
import Models

struct SettingsView: View {
    private let rimeContext = RimeContext.shared
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var syncPath = ""
    @State private var installationID = ""
    @State private var isTesting = false
    @State private var syncAlert: SyncAlert?
    @State private var isConfirmingDelete = false
    @State private var didLoadCredentials = false
    @FocusState private var focusedField: WebDAVField?

    private enum WebDAVField: Hashable {
        case serverURL
        case username
        case password
        case syncPath
        case installationID
    }

    /// 「保存」按钮的置灰判定：仅服务器地址 / 用户名 / 密码三个凭据字段全为空时
    /// 禁用；同步目录与安装 ID 均有默认值，不参与判定。
    private var allCredentialsEmpty: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.isEmpty
    }

    /// 完全访问只影响键盘扩展联网（同步）；per-app 自签基线下主 App 无通道
    /// 感知该状态，故不展示授权提示——未授权的表象就是同步失败。
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
                    LabelledField(title: "服务器地址") {
                        TextField("https://…", text: $serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .onSubmit { testAndSave() }
                            .focused($focusedField, equals: .serverURL)
                            .clearableField(text: $serverURL, isFocused: focusedField == .serverURL)
                    }
                    LabelledField(title: "用户名") {
                        TextField("WebDAV 用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .focused($focusedField, equals: .username)
                            .clearableField(text: $username, isFocused: focusedField == .username)
                    }
                    LabelledField(title: "密码") {
                        SecureField("WebDAV 密码", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .clearableField(text: $password, isFocused: focusedField == .password)
                    }
                    LabelledField(title: "同步目录", infoAction: {
                        syncAlert = SyncAlert(
                            title: "同步目录",
                            message: "WebDAV 服务器上存放各设备同步数据的文件夹名。"
                        )
                    }) {
                        TextField("默认 Rime_Sync", text: $syncPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .syncPath)
                            .clearableField(text: $syncPath, isFocused: focusedField == .syncPath)
                    }
                    LabelledField(title: "安装 ID", infoAction: {
                        syncAlert = SyncAlert(
                            title: "安装 ID",
                            message: "本设备的标识，各设备以此目录名区分。"
                        )
                    }) {
                        TextField("默认 Quill", text: $installationID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .installationID)
                            .clearableField(text: $installationID, isFocused: focusedField == .installationID)
                    }
                    Button {
                        testAndSave()
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isTesting ? "测试中…" : "保存")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isTesting || allCredentialsEmpty)
                } header: {
                    HStack {
                        Text("同步")
                        Button {
                            syncAlert = SyncAlert(
                                title: "同步",
                                message: "通过 WebDAV 双向同步 RIME 自定义短语和朙月拼音输入方案的用户词库。"
                            )
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .tint(.primary)
                        .accessibilityLabel("关于同步")
                    }
                } footer: {
                    Text("调起键盘后，长按空格键 3 秒开始同步。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Text("删除凭据")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    // 挂在按钮上让 iOS 26 把确认弹窗锚定到按钮附近；挂在 Form 级会飘到屏幕顶部。
                    .confirmationDialog(
                        "删除钥匙串中保存的同步凭据？",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("删除", role: .destructive) {
                            deleteCredentials()
                        }
                    }
                }

                Section("日志") {
                    if let url = rimeContext.exportLogURL(),
                       FileManager.default.fileExists(atPath: url.path) {
                        ShareLink(item: url) {
                            Label("导出日志", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Text("暂无日志")
                            .foregroundStyle(.secondary)
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
            .scrollDismissesKeyboard(.immediately)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .padding(.top, 8)
            .navigationTitle("Quill 输入法")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
            .alert(item: $syncAlert) { syncAlert in
                Alert(
                    title: Text(syncAlert.title),
                    message: Text(syncAlert.message),
                    dismissButton: .default(Text("好"))
                )
            }
            .task {
                // 设置页只需要日志与凭据，不创建会话占用共享用户词库。
                if !didLoadCredentials {
                    rimeContext.redirectStderrToLogFile()
                    loadKeyDefaults()
                }
            }
        }
    }

    // MARK: - 凭据

    /// 规范化 WebDAV 服务器地址：无 scheme 时补 `https://`，`http://` 直接拒绝
    /// （Basic Auth 明文走网络会泄露密码）。
    private func normalizedServerURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") {
            return nil
        }
        if trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }

    private func loadKeyDefaults() {
        guard !didLoadCredentials else { return }
        didLoadCredentials = true
        if let creds = WebDAVKeychainStore.load() {
            serverURL = creds.baseURL
            username = creds.username
            password = creds.password
            syncPath = creds.syncPath ?? "Rime_Sync"
            installationID = creds.installationID ?? "Quill"
            // 同步层按凭据设置引擎的安装 ID，保证「保存后测试」里的「本机」标记准确。
            RimeContext.installationID = installationID
        }
    }

    /// 合并「测试连接 + 保存」：点击先测 WebDAV 连通性，成功才写入共享钥匙串；
    /// 无论成功失败都以弹窗提示结果，失败时不保存、也不清空输入框方便修改。
    private func testAndSave() {
        let rawURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = syncPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedID = installationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPath = trimmedPath.isEmpty ? "Rime_Sync" : trimmedPath
        guard !rawURL.isEmpty, !trimmedUser.isEmpty, !password.isEmpty else {
            syncAlert = SyncAlert(title: "保存失败", message: "请填写服务器地址、用户名和密码。")
            return
        }
        guard let trimmedURL = normalizedServerURL(rawURL) else {
            syncAlert = SyncAlert(title: "保存失败", message: "服务器地址必须以 https:// 开头。")
            return
        }
        isTesting = true
        Task {
            defer { isTesting = false }
            let creds = WebDAVCredentials(baseURL: trimmedURL, username: trimmedUser, password: password)
            let client = WebDAVClient(credentials: creds)
            do {
                // 连通性校验：能列出同步目录即可判定服务器 / 凭据有效；
                // 404 = 目录尚未创建（首次连接），服务器与凭据仍有效，由首次同步自动创建。
                do {
                    _ = try await client.listDirectory(relativePath: rootPath)
                } catch WebDAVClient.WebDAVError.serverError(let code) where code == 404 {
                }
                let saveCreds = WebDAVCredentials(
                    baseURL: trimmedURL,
                    username: trimmedUser,
                    password: password,
                    syncPath: trimmedPath.isEmpty ? nil : trimmedPath,
                    installationID: trimmedID.isEmpty ? nil : trimmedID
                )
                do {
                    try WebDAVKeychainStore.save(saveCreds)
                    rimeContext.log("WebDAV credentials saved")
                    syncAlert = SyncAlert(
                        title: "保存成功",
                        message: "已保存到钥匙串。"
                    )
                } catch WebDAVKeychainStore.KeychainError.saveFailed(let status) {
                    let name = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
                    rimeContext.log("WebDAV credentials save failed: OSStatus \(status) \(name)")
                    syncAlert = SyncAlert(
                        title: "保存失败",
                        message: "测试通过，但钥匙串保存失败（\(name) [\(status)]）。"
                    )
                } catch {
                    syncAlert = SyncAlert(title: "保存失败", message: "钥匙串保存失败：\(error.localizedDescription)")
                }
            } catch {
                syncAlert = SyncAlert(title: "保存失败", message: "连接失败：\(error.localizedDescription)")
            }
        }
    }

    /// 清除钥匙串中的凭据（卸载重装不会清钥匙串，需显式删除）。
    private func deleteCredentials() {
        WebDAVKeychainStore.delete()
        serverURL = ""
        username = ""
        password = ""
        syncPath = ""
        installationID = ""
        syncAlert = SyncAlert(title: "已删除", message: "同步凭据已从钥匙串清除。")
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

/// 「测试并保存」等结果的弹窗模型。
private struct SyncAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    SettingsView()
}

/// 输入框上方固定显示其含义（填入内容后仍可辨识该行的用途）；可附一个
/// `infoAction`，title 右侧会出现说明按钮，弹窗解释该字段。
private struct LabelledField<Content: View>: View {
    let title: String
    let infoAction: (() -> Void)?
    let content: Content

    init(
        title: String,
        infoAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.infoAction = infoAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let infoAction {
                    Button(action: infoAction) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 同步输入框聚焦且有文本时，右侧显示清空叉号。
private struct ClearableFieldModifier: ViewModifier {
    @Binding var text: String
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if isFocused, !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .tint(.secondary)
                }
            }
    }
}

extension View {
    /// 聚焦且非空时在输入框右侧显示清除按钮。
    func clearableField(text: Binding<String>, isFocused: Bool) -> some View {
        modifier(ClearableFieldModifier(text: text, isFocused: isFocused))
    }
}