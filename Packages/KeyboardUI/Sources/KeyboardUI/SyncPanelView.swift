import SwiftUI
import Sync
import RimeEngine

/// 键盘同步面板：WebDAV 凭据编辑 + 手动同步按钮。
/// 凭据存键盘扩展私有目录（`WebDAVCredentialStore`），自签下与主 App 无共享通道。
public struct SyncPanelView: View {
    let theme: Theme
    let isSyncing: Bool
    /// 本次启动是否检测到上次键盘异常退出（闪退/Jetsam 标记）。
    let crashedLastRun: Bool
    let onSync: () -> Void

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var syncPath = ""
    @State private var installationID = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false

    public init(theme: Theme, isSyncing: Bool, crashedLastRun: Bool = false, onSync: @escaping () -> Void) {
        self.theme = theme
        self.isSyncing = isSyncing
        self.crashedLastRun = crashedLastRun
        self.onSync = onSync
    }

    /// 「保存」按钮置灰判定：仅三个凭据字段全空时禁用；同步目录与安装 ID 有默认值。
    private var allCredentialsEmpty: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.isEmpty
    }

    public var body: some View {
        VStack(spacing: 6) {
            if crashedLastRun {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("上次键盘异常退出（见日志页）")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
            }
            fieldRow(placeholder: "服务器地址 https://…", text: $serverURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack(spacing: 6) {
                fieldRow(placeholder: "用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                fieldRow(placeholder: "密码", text: $password, secure: true)
            }
            HStack(spacing: 6) {
                fieldRow(placeholder: "同步目录 (默认 Rime_Sync)", text: $syncPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                fieldRow(placeholder: "安装 ID (默认 Quill)", text: $installationID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            HStack(spacing: 8) {
                Button {
                    saveCredentials(testFirst: true)
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(isTesting ? "测试中…" : "保存")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isTesting || isSyncing || allCredentialsEmpty)

                Button(role: .destructive) {
                    WebDAVCredentialStore.delete()
                    serverURL = ""
                    username = ""
                    password = ""
                    syncPath = ""
                    installationID = ""
                    statusMessage = "已删除凭据"
                    statusIsError = false
                } label: {
                    Text("删除凭据")
                        .font(.system(size: 14, weight: .medium))
                        .frame(height: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSyncing)

                Spacer(minLength: 0)

                Button {
                    onSync()
                } label: {
                    HStack(spacing: 4) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(isSyncing ? "同步中…" : "同步")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                .disabled(isSyncing || isTesting)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, theme.keyboardPadding.leading)
        .padding(.bottom, theme.keyboardPadding.bottom)
        .onAppear(perform: loadCredentials)
    }

    /// 单输入行：键盘面板内风格统一的小圆角文本框。
    private func fieldRow(placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.keyCornerRadius, style: .continuous)
                .fill(theme.keyBackground)
        )
    }

    private func loadCredentials() {
        guard let creds = WebDAVCredentialStore.load() else { return }
        serverURL = creds.baseURL
        username = creds.username
        password = creds.password
        syncPath = creds.syncPath ?? "Rime_Sync"
        installationID = creds.installationID ?? "Quill"
    }

    /// 保存前先测连通性（同主 App 原逻辑）；失败不保存、保留输入方便修改。
    private func saveCredentials(testFirst: Bool) {
        let rawURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = syncPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedID = installationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty, !trimmedUser.isEmpty, !password.isEmpty else {
            statusMessage = "请填写服务器地址、用户名和密码"
            statusIsError = true
            return
        }
        guard let trimmedURL = normalizedServerURL(rawURL) else {
            statusMessage = "服务器地址必须以 https:// 开头"
            statusIsError = true
            return
        }
        isTesting = testFirst
        Task {
            defer { isTesting = false }
            let creds = WebDAVCredentials(baseURL: trimmedURL, username: trimmedUser, password: password)
            if testFirst {
                let client = WebDAVClient(credentials: creds)
                let rootPath = trimmedPath.isEmpty ? "Rime_Sync" : trimmedPath
                do {
                    do {
                        _ = try await client.listDirectory(relativePath: rootPath)
                    } catch WebDAVClient.WebDAVError.serverError(let code) where code == 404 {
                    }
                } catch {
                    statusMessage = "连接失败：\(error.localizedDescription)"
                    statusIsError = true
                    return
                }
            }
            do {
                try WebDAVCredentialStore.save(WebDAVCredentials(
                    baseURL: trimmedURL,
                    username: trimmedUser,
                    password: password,
                    syncPath: trimmedPath.isEmpty ? nil : trimmedPath,
                    installationID: trimmedID.isEmpty ? nil : trimmedID
                ))
                statusMessage = "已保存"
                statusIsError = false
            } catch {
                statusMessage = "保存失败：\(error.localizedDescription)"
                statusIsError = true
            }
        }
    }

    /// 规范化 WebDAV 服务器地址：无 scheme 时补 `https://`，`http://` 拒绝（Basic Auth 明文）。
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
}
