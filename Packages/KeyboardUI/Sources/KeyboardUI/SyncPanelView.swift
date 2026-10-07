import SwiftUI

struct SyncPanelView: View {
    let model: SyncSettingsModel
    let inputState: InputState
    let theme: Theme
    let hasFullAccess: () -> Bool
    let onSync: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(SyncSettingsModel.Field.allCases) { item in
                            field(item).id(item)
                            if item != .installationID { Divider().padding(.leading, 14) }
                        }
                    }
                    .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectHidden(true, for: .all)
                .onChange(of: model.editingField) { _, field in
                    if let field {
                        withAnimation(.easeOut(duration: 0.18)) { reader.scrollTo(field, anchor: .center) }
                    }
                }
            }
            if let text = model.message, model.isError {
                message(text, isError: true)
            } else if model.hasUnsavedChanges && model.hasSavedCredentials {
                message("修改后请先保存。", isError: false)
            } else if let text = model.message {
                message(text, isError: model.isError)
            }
            if confirmingDelete {
                HStack {
                    Text("删除已保存的凭据？")
                    Spacer()
                    Button("取消") { confirmingDelete = false }
                    Button("删除凭据", role: .destructive) { model.delete(); confirmingDelete = false }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
            } else {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            model.editingField = nil
                            Task { await model.save(hasFullAccess: hasFullAccess()) }
                        } label: {
                            Label(model.isTesting ? "测试中" : "保存", systemImage: "checkmark")
                        }
                        .buttonStyle(.glass)
                        .disabled(model.allCredentialsEmpty || (model.hasSavedCredentials && !model.hasUnsavedChanges) || model.isTesting || inputState.isSyncing)
                        Button("删除凭据", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .buttonStyle(.glass)
                            .disabled(!model.hasSavedCredentials || model.isTesting || inputState.isSyncing)
                        Spacer(minLength: 0)
                        Button {
                            if model.requireFullAccess(hasFullAccess()) { onSync() }
                        } label: {
                            HStack(spacing: 5) {
                                if inputState.isSyncing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text(syncTitle)
                            }
                            .frame(width: 80, height: 24)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                        .controlSize(.regular)
                        .disabled(!model.hasSavedCredentials || model.hasUnsavedChanges || model.isTesting || inputState.isSyncing)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .controlSize(.regular)
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 10)
        .onAppear { model.load() }
    }

    private var syncTitle: String {
        if inputState.isSyncing { return "同步中" }
        switch inputState.sync.result {
        case .completed: return "同步完成"
        case .failed: return "同步失败"
        case nil: return "同步"
        }
    }

    private func message(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    private func field(_ field: SyncSettingsModel.Field) -> some View {
        let editing = model.editingField == field
        let value = model.values[field, default: ""]
        return HStack(spacing: 10) {
            Button { model.editingField = field } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        Text(field.title).foregroundStyle(theme.keyForeground)
                        if field.isRequired {
                            Text("*").foregroundStyle(.red)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    HStack(alignment: .top, spacing: 2) {
                        Text(value.isEmpty && !editing ? field.placeholder : value)
                            .foregroundStyle(value.isEmpty ? theme.keyForeground.opacity(0.55) : theme.keyForeground)
                            .lineLimit(editing ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if editing {
                            Capsule().fill(Color.accentColor).frame(width: 2, height: 18)
                        }
                    }
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑\(field.title)")
            .accessibilityHint(field.isRequired ? "必填" : "留空使用默认值")
            .accessibilityValue(value)
            if editing {
                Button {
                    if let text = UIPasteboard.general.string { model.append(text) }
                } label: { Image(systemName: "document.on.clipboard") }
                    .accessibilityLabel("粘贴")
                Button(action: model.clearField) { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("清空字段")
                    .disabled(value.isEmpty)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 68)
        .disabled(model.isTesting || inputState.isSyncing)
    }
}
