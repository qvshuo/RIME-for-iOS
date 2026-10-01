import SwiftUI

struct LogPanelView: View {
    let isVisible: Bool
    let theme: Theme
    let onExport: () -> Void
    @State private var tail = ""
    private let diagnostics = KeyboardDiagnostics.shared

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                Text(tail.isEmpty ? "暂无日志" : tail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.keyForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .accessibilityIdentifier("diagnosticLog")
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 18))
            Button(action: onExport) {
                Label("导出", systemImage: "square.and.arrow.up")
                    .frame(width: 80, height: 20)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .controlSize(.large)
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        // 视图移出层级时 SwiftUI 取消任务，日志页外没有轮询或定时器。
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                let latest = await Task.detached(priority: .utility) { diagnostics.tail() }.value
                guard !Task.isCancelled else { return }
                if tail != latest { tail = latest }
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
}
