import SwiftUI

struct LogPanelView: View {
    let theme: Theme
    let onExport: () -> Void
    @State private var tail = ""
    private let diagnostics = KeyboardDiagnostics.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("导出", systemImage: "square.and.arrow.up", action: onExport)
                    .buttonStyle(.glass)
                Spacer()
            }
            .font(.system(size: 14))
            ScrollView {
                Text(tail.isEmpty ? "暂无日志" : tail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.keyForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .accessibilityIdentifier("diagnosticLog")
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .background(theme.keyBackground, in: RoundedRectangle(cornerRadius: 18))
            Text("每秒自动更新 · 最近日志")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        // 视图移出层级时 SwiftUI 取消任务，日志页外没有轮询或定时器。
        .task {
            while !Task.isCancelled {
                let latest = await Task.detached(priority: .utility) { diagnostics.tail() }.value
                guard !Task.isCancelled else { return }
                tail = latest
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
}
