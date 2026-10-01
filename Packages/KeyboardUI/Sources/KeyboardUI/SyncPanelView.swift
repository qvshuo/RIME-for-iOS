import SwiftUI

struct SyncPanelView: View {
    let model: SyncSettingsModel
    let inputState: InputState
    let theme: Theme
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
                    .background(theme.keyBackground, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.editingField) { _, field in
                    if let field {
                        withAnimation(.easeOut(duration: 0.18)) { reader.scrollTo(field, anchor: .center) }
                    }
                }
            }
            if confirmingDelete {
                HStack {
                    Text("删除保存的配置？")
                    Spacer()
                    Button("取消") { confirmingDelete = false }
                    Button("删除", role: .destructive) { model.delete(); confirmingDelete = false }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
            } else {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            model.editingField = nil
                            Task { await model.save() }
                        } label: {
                            Label(model.isTesting ? "测试中" : "保存", systemImage: "checkmark")
                        }
                        .buttonStyle(.glass)
                        .disabled(model.allCredentialsEmpty || model.isTesting || inputState.isSyncing)
                        Button("删除", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .buttonStyle(.glass)
                            .disabled(!model.hasSavedCredentials || model.isTesting || inputState.isSyncing)
                        Spacer(minLength: 0)
                        Button(action: onSync) {
                            HStack(spacing: 5) {
                                if inputState.isSyncing { ProgressView().controlSize(.mini) }
                                Text(inputState.isSyncing ? "同步中" : "同步")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!model.hasSavedCredentials || model.hasUnsavedChanges || model.isTesting || inputState.isSyncing)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .controlSize(.regular)
                .padding(.horizontal, 12)
            }
            if model.hasUnsavedChanges && model.hasSavedCredentials {
                message("修改后请先保存。", isError: false)
            } else if let text = model.message {
                message(text, isError: model.isError)
            }
        }
        .padding(.bottom, 10)
        .onAppear { model.load() }
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
                HStack(alignment: .center, spacing: 12) {
                    Text(field.title)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    HStack(spacing: 2) {
                        Text(value.isEmpty ? field.placeholder : value)
                            .foregroundStyle(value.isEmpty ? theme.keyForeground.opacity(0.4) : theme.keyForeground)
                            .lineLimit(1)
                            .truncationMode(editing ? .head : .tail)
                        if editing {
                            Capsule().fill(Color.accentColor).frame(width: 2, height: 18)
                        }
                    }
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑\(field.title)")
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
        .frame(minHeight: 44)
        .background(editing ? Color.accentColor.opacity(0.07) : Color.clear)
        .disabled(model.isTesting || inputState.isSyncing)
    }
}
