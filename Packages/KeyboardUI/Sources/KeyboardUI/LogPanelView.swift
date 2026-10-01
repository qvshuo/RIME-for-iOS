import SwiftUI
import RimeEngine
import CoreTransferable
import UniformTypeIdentifiers

struct LogPanelView: View {
    let theme: Theme
    @State private var tail = ""
    @State private var errorMessage: String?
    @State private var confirmingClear = false
    @State private var isClearing = false
    @State private var refreshedAt: Date?
    private let diagnostics = KeyboardDiagnostics.shared

    var body: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if confirmingClear {
                        Text("清空日志？").font(.system(size: 14))
                        Spacer()
                        Button("取消") { confirmingClear = false }
                        Button("清空", role: .destructive, action: clear)
                    } else {
                        ShareLink(item: DiagnosticArchive(), preview: SharePreview("Quill 日志")) {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                            .accessibilityHint("重新读取键盘和引擎的最新日志")
                        Button("清空", role: .destructive) { confirmingClear = true }
                    }
                }
                .font(.system(size: 14))
                .buttonStyle(.glass)
                .controlSize(.regular)
                .disabled(isClearing)
            }
            ScrollView {
                Text(tail.isEmpty ? "暂无日志" : tail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.keyForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(theme.keyBackground, in: RoundedRectangle(cornerRadius: 18))
            HStack {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if isClearing {
                    Text("正在清空…")
                } else if let refreshedAt {
                    Text("已刷新 \(refreshedAt.formatted(date: .omitted, time: .standard))")
                }
                Spacer()
                Text("最近日志")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        tail = diagnostics.tail()
        refreshedAt = .now
        errorMessage = nil
    }

    private func clear() {
        confirmingClear = false
        isClearing = true
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try RimeContext.shared.clearLog()
                    try KeyboardDiagnostics.shared.clear()
                }.value
                refresh()
            } catch { errorMessage = error.localizedDescription }
            isClearing = false
        }
    }
}

private struct DiagnosticArchive: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            SentTransferredFile(try KeyboardDiagnostics.shared.export())
        }
    }
}
