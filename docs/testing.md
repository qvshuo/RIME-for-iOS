# 核心测试

当前为 41 项测试、14 个 suite（原 69 项同类情形合并）。测试目标为 `RIMECoreTests`，是 hostless 单元测试 bundle，使用 Swift Testing。测试源按行为分组，名称与生产类型对应。运行命令见 [AGENTS.md](../AGENTS.md#build-test-and-package)。

| 目录 | 保留的行为 | 验证方法 |
|---|---|---|
| Input | Shift 状态、各布局/语言路由、宿主类型变化、混合预输入、一次性提交和 Unicode 光标 | 注入时钟；真实 librime 最小方案；真实 UITextView 代理 |
| Layout | 行宽守恒、z/s 与 m/k 对齐、长回车文案、零权重、候选换行/首行对齐、字体缓存、深浅色对比 | 纯计算及真实字体测量 |
| Sync | HTTPS/路径边界、PROPFIND 正常与损坏响应、凭据保存/删除、草稿隔离、失败保留旧配置、文件筛选和暂存清理 | 临时文件和可注入传输，不访问真实服务器 |
| Sync | 超时后等待维护完成再返回 | continuation 控制执行顺序，不依赖定时等待 |
| Diagnostics | UTF-8 截断、日志限额/轮转、并发写入、旧控制器不能删除新会话标记 | 临时目录和并发写入 |
| Rendering | 三类页面在两种主题下的内在尺寸 | UIHostingController.sizeThatFits |

本次合并布局/空格/Shift 的同类情形，删除 KeyAction 简单属性别名、toast 固定文案等低价值测试，主题断言合并为状态与对比两组；候选测试合并正常/窄行/箭头让位和三种高亮位置。未删除输入排序、插件注册、引擎重建保护、同步失败/取消、路径安全或并发日志等回归。

`CompositionCommitTests` 使用进程级真实 librime，因此初始化和清理必须完整并持引擎锁。它既验证原生 ASCII 通道，也验证包含全角标点的字面组合。`TextViewProxy` 放在 `Tests/Input/Fixtures/`，仅模拟宿主代理，不复制生产提交逻辑。

人工/端到端检查：单击及双击 Shift → 字母 → 数字/符号 → 空格；普通 nihao 候选/展开/选择；菜单不显示当前页面；同步编辑不写入宿主；日志只在页面可见时自动更新；导出和关闭后恢复高度；主应用名称与启用状态。键盘需先在系统设置中启用，Unsigned 模拟器安装不包含 App Group 权限。

UIKit 分享、系统键盘启用和 Liquid Glass 的测试需要实际运行宿主。临时 UI 宿主的结果作为本地验证记录，不混入单元测试数量。截图尺寸测试不能证明玻璃效果或系统弹出框正常。真实 WebDAV、自签真机和内存 footprint 仍需独立验证。
