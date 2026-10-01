# 实现评估：RIME for iOS、fcitx5-ios、Squirrel

评估日期：2026-10-01。结论：保留直接 librime、预构建数据和精简键盘的架构。最值得借鉴的是输入框身份隔离、候选增量读取、可见视图生命周期及可复现的内存诊断。多引擎、撤销/重做、运行时部署应等明确需求出现后再引入。

## 样本与复现

| 项目 | 实际检查的版本 | 获取结果 |
|---|---|---|
| RIME for iOS | 本轮 2.0.0（16），基于本地 main `8061ee1` | 更名、注释和测试收敛后的本仓库源码；librime 仍为 1.16.0 |
| fcitx5-ios | master `840a91501d3cfeb5227c3962dc8f2906f02db0bc`，提交时间 2026-10-01 06:21（北京时间） | 对现有干净克隆执行 git pull --ff-only；从 `3084806` 更新。获取固定版本的 fcitx5、fcitx5-rime、libime 和键盘布局子模块 |
| Squirrel | 最新正式 release **1.1.2**，发布于 2026-01-14；源码 `876adebaf2f612951dcdca8a591de65401222b9a` | GitHub releases/latest API 确認正式版本；安装包已下载，原有源码及 librime/plum/Sparkle 的固定版本已核对 |

Squirrel 的浮动 nightly 标签不作为正式版本基线。下载文件：父目录 `reference-downloads/squirrel-1.1.2/Squirrel-1.1.2.pkg`，25,498,033 字节，SHA-256：

```
614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287
```

Squirrel 的 librime pin 是 `a251145d`（1.16.0），与本项目一致；本轮无需更换引擎二进制。Squirrel 的已有 Sparkle 工作区修改保留，没有为了比较覆盖它。fcitx5-ios 其余多引擎/打包子模块未全部下载或构建，源码判断以已检查的前端、补丁和相关引擎为界。

版本依据：[fcitx5-ios 固定提交](https://github.com/fcitx-contrib/fcitx5-ios/commit/840a91501d3cfeb5227c3962dc8f2906f02db0bc)、[Squirrel 正式 release](https://github.com/rime/squirrel/releases/tag/1.1.2)、[Squirrel 子模块定义](https://github.com/rime/squirrel/blob/1.1.2/.gitmodules)。

## 功能与实现对照

| 方面 | RIME for iOS | fcitx5-ios 最新代码 | Squirrel 1.1.2 |
|---|---|---|---|
| 平台与范围 | iOS 26+，单 RIME 键盘 | iOS 16.3+，多引擎、多扩展 | macOS，物理键盘 + InputMethodKit |
| 引擎链路 | Swift 直接调用 librime；递归锁保护，维护另有串行队列 | fcitx C++ 事件调度器 → iOS frontend → Swift 主线程 | 输入事件转换 X11 键码后调用 librime |
| 输入框隔离 | 会话归属 + 输入框身份隔离；旧后台快照按代次丢弃 | 回调携带 program + documentIdentifier，主线程执行前核对当前输入框 | IMK client 与对应 session 绑定，按应用读取选项 |
| 大写混合预输入 | 自有字面组合支持全角标点；Space/Return/选候选整段提交 | 通用虚拟键修饰状态和引擎输入路径 | 主要由 librime ascii_composer 及配置决定 |
| 提交与宿主光标 | 清除 marked text → unmark → 一次插入合并文本 | commitString 直接插入；另有 Unicode 周围文本删除及光标操作 | IMK client.insertText，桌面标记文本和客户端 API |
| 候选 | 当前页 9 个，展开补至 77 个；惰性视图、字体宽度缓存 | 横向/网格临近末尾读取下一批，区分 bulk 和分页，支持候选动作 | 可配置横/竖/线性浮动面板，分页、注释和内联预编辑 |
| 编辑能力 | 连续退格、双空格句号、基础切换 | 滑动删除、光标移动、撤销/重做、周围文本、数字键盘 | 实体修饰键、和弦输入、桌面应用选项 |
| 生命周期 | 进程引擎共享，隐藏期拒绝输入并暂停日志；保留草稿视图 | 可见时装载 SwiftUI 树，隐藏时拆卸；文档轮询仅可见时运行 | macOS 输入法进程，IMK 激活/停用管理 |
| 数据部署 | 构建期生成，扩展启动不部署 | RIME 补丁不在键盘启动部署；部署动作转交主应用 | 支持运行时维护/部署、方案与配置更新 |
| 数据互通 | 可选 App Group；无权限时私有容器，WebDAV 手动传用户词库/短语 | App Group；无权限时通过主应用本地服务与键盘同步配置，支持归档导入/导出 | librime 用户数据同步到本地 sync 目录；前端不内置 WebDAV 客户端 |
| 诊断 | 事件与 native 日志有界、约 1 MiB 导出，不记录按键 | 文档/进程诊断与可复现的内存调查；stderr 在启动截断，进程内继续追加 | native 日志及桌面配置/维护反馈 |
| 测试 | 真引擎/真 UITextView + 可注入同步、纯排版和日志边界 | Swift 撤销/重做单元测试及 Appium 端到端入口 | 本次以正式版前端/引擎源码为准，未运行桌面自动化 |

实现依据：[fcitx 宿主控制器](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/keyboard/KeyboardViewController.swift)、[输入框校验桥](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/iosfrontend/iosfrontend.swift)、[候选条](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/uipanel/CandidateBar.swift)、[RIME iOS 补丁](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/patches/rime.patch)、[数据管理](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/src/DataManager.swift)、[Squirrel 输入控制器](https://github.com/rime/squirrel/blob/1.1.2/sources/SquirrelInputController.swift)、[Squirrel 维护/同步](https://github.com/rime/squirrel/blob/1.1.2/sources/SquirrelApplicationDelegate.swift)。

## 值得借鉴的部分

### 优先：输入框身份与可见期检查

fcitx5-ios 不只确认控制器仍存在，还核对异步输出属于哪一个 documentIdentifier；隐藏期间停止接收引擎命令。这样即使同一个控制器快速切换 TextField，也不会把延迟输出写入新字段。

本项目多数按键处理同步调用，不移植 fcitx 调度器。本轮已在宿主字段身份改变时丢弃旧组合，并处理系统暂时无法提供 UUID 的情况；隐藏时拒绝输入、暂停日志；后台候选快照使用发布代次丢弃旧结果。实际宿主新增两个相同类型 UITextView 的切换回归。没有记录字段内容或文档标识。

### 优先：候选增量读取

fcitx5-ios 在横向滚动和网格接近末尾时才请求下一批。本项目已经有 LazyHStack/LazyVStack，但数据层展开时只取固定 77 个；“惰性视图”与“候选按需读取”是两个问题。

当前限定不改变功能范围，继续保留 77 个候选上限及惰性视图/宽度缓存，没有添加 load-more 功能。增加候选、preedit、高亮的等值检查，减少不改变界面的发布；分页接口仍作为以后扩展时的参考。

### 优先：内存测量方法

fcitx5-ios 9 月调查区分 live heap、physical footprint、file-backed mapping 和初次预测加载；通过单变量恢复定位出重复 @Published 等值赋值导致的周期增长。其 libime Apple 补丁将 KenLM 加载改为 LAZY，真机全模型测试报告冷启动 footprint 约减少 33 MiB。

这项数值属于 **libime/fcitx5-ios 的特定模型、设备和测试序列**。RIME 的词典已经使用 mapped_file；本项目还加载 octagram，不能据此推导本项目也会减少 33 MiB。应该先对本项目 Release 真机做冷启动、首次候选、100 次提交、10 分钟静置与多宿主切换的相同采样；确认具体堆分配后才改模型加载。本项目使用 Observation 的状态，不应直接套用 @Published 的内部行为结论。

方法依据：[调查流程](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/docs/memory.md)、[9 月实测记录](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/docs/memory-investigations/chinese-2026-09.md)、[libime 补丁](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/patches/libime.patch)、[librime 映射文件实现](https://github.com/rime/librime/blob/1.16.0/src/rime/dict/mapped_file.cc)。

### 有测量后再做：隐藏时释放 SwiftUI 树

fcitx5-ios 最新控制器在 viewWillDisappear 拆卸 hostingController，避免 UIKit 保留多个非可见控制器时各自保留 SwiftUI 树。本项目目前将树保留至控制器销毁。

这是有价值的优化方向，但本项目将凭据草稿、编辑状态和按压状态放在视图树里；直接拆卸会丢失草稿，也可能因导出覆盖引发不必要重建。应先测多宿主隐藏控制器的驻留，再把需要保留的草稿移至独立生命周期、处理分享覆盖，最后比较重建延迟与内存收益。不能只删视图就称为无风险优化。

### 保留：Squirrel 的引擎语义和一次性提交纪律

Squirrel 先消费 RimeCommit，再读取并展示上下文；未处理键交回客户端，模式切换规则由引擎配置控制。本项目应继续以这个顺序与原生 librime 作为语义基线。

“按 Shift 后全部字符预输入，Space 确认”是本项目明确产品规则。Squirrel 自身并未定义一份与该规则完全相同的全角符号缓冲；其行为受 schema/ascii_composer 配置影响。保留本项目 Unicode 字面组合和真实宿主的单次插入修复，不用桌面 client.insertText 替换 iOS marked-text 提交路径。

## 暂缓或不采纳

| 方案 | 评估 |
|---|---|
| 整套 fcitx 核心、多引擎桥 | 对单 RIME 产品收益有限，会引入第二套生命周期/事件状态和构建链；异步线程并非自动更快 |
| 撤销/重做和完整编辑工具栏 | 上游需要文档轮询、行状态历史、Unicode range 计算和切换保护；UITextDocumentProxy 只暴露部分上下文，复杂度显著。出现明确需求后独立设计、限制历史并验证隐私/内存 |
| 主应用动态部署及方案导入 | 技术上可借鉴“重工作放主应用”，但无 App Group 自签基线还要跨进程交付编译结果；不能简单搬桌面部署，更不能在扩展中强制部署 |
| 通过本地 HTTP/magic text 同步主应用配置 | 上游解决多引擎配置交付问题；本项目当前在键盘完成配置，暂无这条链路需求。若未来支持方案导入，再单独评估 |
| Squirrel 的主题、应用选项、和弦输入 | 桌面候选窗口/IMK 能力不等同于 iOS 虚拟键盘；不宜直接移植 |
| 照搬上游诊断/日志全文 | 文档诊断可能涉及周围文本；本项目仍保持不记录按键/密码、有界日志。不为借鉴诊断而扩大采集范围 |

fcitx5-ios 源码为 GPLv3，本项目应用源码为 MIT。可学习设计和测量方法；若复制实现，需要单独处理许可兼容性。本轮没有复制上游业务实现，也未将其作为新运行依赖。[上游 LICENSE](https://github.com/fcitx-contrib/fcitx5-ios/blob/840a91501d3cfeb5227c3962dc8f2906f02db0bc/LICENSE)

## 本轮实际采用与边界

本轮实际采用：字段身份隔离、隐藏期输入/轮询门禁、后台快照代次、候选和日志等值更新检查；保留现有草稿、候选上限、引擎与功能范围。前一轮的职责命名、核心测试收敛及诊断边界保持不变。依赖的逐项核对与插件对齐见 [dependencies.md](dependencies.md)。

增量候选和隐藏时释放整棵视图树仍暂缓，避免扩大范围或丢失凭据草稿。评估基于固定源码与上游报告；未在本机完整构建或跑性能 A/B 对比三者，也未将上游性能数字描述为本项目实测。键盘扩展的历史 ~77 MiB 限制是设备/OS 观测，实际预算需要真机测量。
