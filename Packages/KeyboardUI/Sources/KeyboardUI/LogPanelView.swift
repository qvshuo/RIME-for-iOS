import SwiftUI
import RimeEngine
import CoreTransferable
import UniformTypeIdentifiers

struct LogPanelView: View {
    let theme: Theme
    @State private var tail = ""
    @State private var errorMessage: String?
    @State private var confirmingClear = false
    private let diagnostics = KeyboardDiagnostics.shared

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                ShareLink(item: DiagnosticArchive(), preview: SharePreview("Quill 日志")) {
                    Label("导出全部", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新日志")
                Button("清空", role: .destructive) { confirmingClear = true }
                    .confirmationDialog("清空键盘和引擎日志？", isPresented: $confirmingClear, titleVisibility: .visible) {
                        Button("清空", role: .destructive) {
                            do {
                                try diagnostics.clear()
                                try RimeContext.shared.clearLog()
                                refresh()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
            }
            .font(.system(size: 13))
            .buttonStyle(.bordered)
            .controlSize(.small)
            ScrollView {
                Text(tail.isEmpty ? "暂无日志" : tail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.keyForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .background(theme.keyBackground, in: RoundedRectangle(cornerRadius: theme.keyCornerRadius))
            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, theme.keyboardPadding.leading)
        .padding(.bottom, theme.keyboardPadding.bottom)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        tail = diagnostics.tail()
        errorMessage = nil
    }
}

private struct DiagnosticArchive: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            SentTransferredFile(try KeyboardDiagnostics.shared.export())
        }
    }
}
