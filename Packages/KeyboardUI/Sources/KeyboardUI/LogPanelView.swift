import SwiftUI
import RimeEngine

/// 键盘日志面板：查看 / 导出 / 清空。崩溃报告在下次启动时写入日志文件。
/// 键盘专用日志独立于 RIME 引擎日志（`keyboard.log`），查闪退不受引擎输出干扰。
public struct LogPanelView: View {
    let theme: Theme
    let rimeContext: RimeContext
    /// 清空回调（控制器侧完成实际删除并记录节点）。
    let onClear: () -> Void

    /// 面板打开时读取的日志尾部快照（行级，上限见实现）。
    @State private var logTail: String = ""
    /// 清空确认（避免误触丢日志）。
    @State private var isConfirmingClear = false

    public init(theme: Theme, rimeContext: RimeContext, onClear: @escaping () -> Void) {
        self.theme = theme
        self.rimeContext = rimeContext
        self.onClear = onClear
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if let url = rimeContext.keyboardLogURL(),
                   FileManager.default.fileExists(atPath: url.path) {
                    ShareLink(item: url) {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .frame(height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Text("暂无日志")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Text("清空")
                        .font(.system(size: 14, weight: .medium))
                        .frame(height: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    "清空键盘日志？",
                    isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button("清空", role: .destructive) {
                        onClear()
                        logTail = ""
                    }
                }
            }

            ScrollView {
                Text(logTail.isEmpty ? "（空）" : logTail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: theme.keyCornerRadius, style: .continuous)
                    .fill(theme.keyBackground)
            )
        }
        .padding(.horizontal, theme.keyboardPadding.leading)
        .padding(.bottom, theme.keyboardPadding.bottom)
        .onAppear(perform: reloadTail)
    }

    /// 读取日志尾部最近 8KB（约百余行），面板只做概览，全文走导出。
    private func reloadTail() {
        guard let url = rimeContext.keyboardLogURL(),
              let handle = try? FileHandle(forReadingFrom: url) else {
            logTail = ""
            return
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 8192
        let offset = size > window ? size - window : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        var text = String(data: data, encoding: .utf8) ?? ""
        // 非整行起点时丢弃首个残行。
        if offset > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        logTail = text
    }
}
