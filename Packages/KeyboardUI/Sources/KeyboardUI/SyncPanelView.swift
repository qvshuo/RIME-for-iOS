import SwiftUI

struct SyncPanelView: View {
    let model: SyncSettingsModel
    let inputState: InputState
    let theme: Theme
    let onSync: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                field(.server)
                HStack(spacing: 7) { field(.username); field(.password) }
                HStack(spacing: 7) { field(.path); field(.installationID) }
                HStack(spacing: 10) {
                    Button {
                        Task { await model.save() }
                    } label: {
                        Label(model.isTesting ? "测试中" : "保存", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.allCredentialsEmpty || model.isTesting || inputState.isSyncing)
                    Button("删除", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(.bordered)
                        .disabled(!model.hasSavedCredentials || model.isTesting || inputState.isSyncing)
                        .confirmationDialog("删除保存的同步凭据？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("删除", role: .destructive) { model.delete() }
                        }
                    Spacer(minLength: 0)
                    Button(action: onSync) {
                        HStack(spacing: 5) {
                            if inputState.isSyncing { ProgressView().controlSize(.mini) }
                            Text(inputState.isSyncing ? "同步中" : "同步")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasSavedCredentials || model.hasUnsavedChanges || model.isTesting || inputState.isSyncing)
                }
                .font(.system(size: 13, weight: .medium))
                .controlSize(.small)
                if model.hasUnsavedChanges && model.hasSavedCredentials {
                    Text("修改后请先保存。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let message = model.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(model.isError ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, theme.keyboardPadding.leading)
            .padding(.bottom, theme.keyboardPadding.bottom)
        }
        .onAppear { model.load() }
    }

    private func field(_ field: SyncSettingsModel.Field) -> some View {
        Button { model.editingField = field } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.title).font(.system(size: 10)).foregroundStyle(.secondary)
                let value = model.values[field, default: ""]
                Text(value.isEmpty ? field.placeholder : field == .password ? String(repeating: "•", count: min(value.count, 12)) : value)
                    .font(.system(size: 13))
                    .foregroundStyle(value.isEmpty ? theme.keyForeground.opacity(0.45) : theme.keyForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.keyBackground, in: RoundedRectangle(cornerRadius: theme.keyCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(model.isTesting || inputState.isSyncing)
        .accessibilityLabel("编辑\(field.title)")
    }
}

struct CredentialEditorBar: View {
    let model: SyncSettingsModel
    let theme: Theme
    @State private var showingPassword = false

    var body: some View {
        HStack(spacing: 7) {
            if let field = model.editingField {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    let value = model.values[field, default: ""]
                    Text(field == .password && !showingPassword ? String(repeating: "•", count: min(value.count, 24)) : value.isEmpty ? field.placeholder : value)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if field == .password {
                    Button { showingPassword.toggle() } label: {
                        Image(systemName: showingPassword ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(showingPassword ? "隐藏密码" : "显示密码")
                }
            }
            Button { if let text = UIPasteboard.general.string { model.append(text) } } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .accessibilityLabel("粘贴")
            Button(action: model.clearField) { Image(systemName: "xmark.circle") }
                .accessibilityLabel("清空字段")
            Button("完成") { model.editingField = nil }
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.keyForeground)
        .padding(.horizontal, theme.keyboardPadding.leading + 2)
        .frame(height: theme.candidateBarHeight + theme.keyboardPadding.top)
        .onChange(of: model.editingField) { _, _ in showingPassword = false }
    }
}
