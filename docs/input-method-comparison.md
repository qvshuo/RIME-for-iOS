# 输入法对比：Quill × Squirrel × Hamster × fcitx5-ios

> 基准 = Quill（本仓库）。对比对象：父目录同级 clone 的 `squirrel`（librime 上游 macOS 版）、`Hamster`（iOS）、`fcitx5-ios`（iOS）。
> 本文记录四个项目在「功能面」与「实现面」的可比事实，供 Quill 后续取舍参考。

## 0. 项目定位速览

| | Quill | Squirrel | Hamster | fcitx5-ios |
|---|---|---|---|---|
| 平台 | iOS（App + 键盘扩展） | macOS（输入法进程，无扩展概念） | iOS（App + 键盘扩展） | iOS（App + 多个键盘扩展） |
| 引擎 | librime（预编译 xcframework） | librime（dylib + 源码构建） | librime（RimeKit 包封装） | fcitx5 核心（RIME 是其一插件引擎） |
| 前端 | SwiftUI 全自研 | AppKit / InputMethodKit | UIKit（KeyboardKit fork）/ SwiftUI | SwiftUI（uipanel） |
| 架构形态 | 3 个 SwiftPM 包 + C 桥 | 单 target + Makefile + 打包 | ~6 个 SwiftPM 包 | CMake + 静态库 + 共享库 |
| 方案模型 | 锁死 `luna_pinyin` 单方案 | 方案交给 librime | 多方案可切换 | 多引擎（pinyin/rime/mozc…） |
| 特点 | 最小精简、无部署栈、WebDAV 手动同步 | 经典桌面 RIME、真部署、明文配置 | 功能最多：九宫/T9/云端/配色全上 | 复刻整个 fcitx5 框架，可扩展引擎 |

**一句话**:Quill = iOS 最小 RIME 复刻；Squirrel = macOS 桌面标杆、零虚拟键盘；Hamster = iOS 功能最全 RIME；fcitx5-ios = 把整套 fcitx5 移植到 iOS，RIME 只是插件之一。

---

## 1. 引擎桥接与内存模型

### Quill
- `RimeEngine` 直接链接 librime.a（Frameworks 内 xcframework），`RimeEngineC` 暴露 `_stdbool` 风味 C API；Swift 侧 `RimeContext`（`@Observable` 单例）按 Lifecycle / Input / Directories / Logging 拆分扩展文件。
- `RimeTraits` / `RimeContext` / `RimeCommit` 都要求手动写 `data_size`，否则 `RimeGetContext`/`RimeGetCommit` 返回 false。
- 同步阻塞调用：librime `RimeProcessKey` → `RimeGetCommit`（一次性，`pollCommit()` 消费）→ `RimeGetContext`。
- 内存极敏感（iOS 扩展 `~77MB` 上限）→ **禁 deploy**，数据预构建（见 §3）。

### Squirrel（macOS）
- 同样走 `rime_get_api_stdbool().pointee`，并有 `rimeStructInit()`（清零 + 设 `data_size`）——与 Quill 完全同源的技术。
- 进程即输入法 App（InputMethodKit），可任意 deploy，无内存/沙盒限制。
- 蓝图：主线程事件循环，librime 自身在运行时内部有线程池（同步调用掩盖了它）。

### Hamster
- 用独立的 SwiftPM 包 `RimeKit`：`Rime.shared` 单例，封装 `start(sharedSupportDir:userDataDir:maintenance:fullCheck:)`。
- `RimeContext`（@StateObject/@Published 分发）：Combine + `rimeContext` / `suggestions` / `optionState`；`userInputKey` 用 Subject 驱动。
- 部署区分「主 App 内存富余」与「扩展省内存」两个角色，见 §3。

### fcitx5-ios
- 不直接用 librime——把 **fcitx5 核心（C++20）** 搬运过来，`runtime_main.cpp` 跑 `fcitx::Instance`，且跑在**独立线程** + 「事件调度 → SwiftUI」桥。
- Swift ↔ C++ 走 protocol：`key/commitString/setPreedit/…`；RIME 作为 fcitx5 的插件（`fcitx-rime`）被 `libime` 静态链入。

**要点**：Quill / Squirrel 同步直调 librime；Hamster 同步调用但用 Combine 分发；fcitx5-ios 是真正的异步多线程 + 事件桥——这是它和其余三者架构代差所在。

---

## 2. 输入链路与候选输出

### 前端截获方式
| 项目 | 渲染 | 载体 |
|---|---|---|
| Quill | SwiftUI（键盘视图） | 键盘扩展，直接 `textDocumentProxy` |
| Squirrel | 候选窗口（面板） + 无虚拟键盘 | 物理键盘 → IMK，`client.setMarkedText` |
| Hamster | SwiftUI（Key/九键） | 扩展，`textDocumentProxy` + `setMarkedText` |
| fcitx5-ios | SwiftUI（uipanel） | 扩展，`UITextDocumentProxy` + `forwardKey` |

### 细节差异
- **Squirrel**：键盘事件转 X11 键码发给 librime；预编辑 inline 或候选窗口双模；支持 `chord typing`（多重修饰键组合）等 librime 功能。仅桌面端。
- **Hamster**：多了「成对符号自动插入闭合」「删除成对符号」「光标居中」等输入代理特设逻辑；T9 九键有自己的拼音映射 trie（`replaceDyadicPinyin`）。
- **fcitx5-ios**：`forwardKey` 处理候选行的上下行/Home/End/退格等整行操作，还内置「滑动退格删除」「long press 连续删除」。

这类「in-extension 文本操作」Quill 目前几乎没有，只做基础 insert/delete。

---

## 3. 部署 / 数据生命周期

| | Quill | Squirrel | Hamster | fcitx5-ios |
|---|---|---|---|---|
| 部署方式 | **禁部署**：`prebuilt_data_dir=SharedSupport/build`（macOS 上 rime_deployer 预先出 .bin），`start() = setup→initialize` | **安装时部署**：打包脚本内置 `rime_deploy` 首次生成数据 | **主 App 部署**：`deployment(configuration:)` 在 App（内存富余）维护 `fullCheck`，把数据copy到 AppGroup | **主 App 部署**：键盘扩展启动时不做 maintainance；改动 schema 后跳回主 App 触发 |
| 语言数据来源 | 构建期，脚本 `scripts/build-prebuilt-data.sh` | 源码构建 + `data/` 提交 | App bundle 内置数据 + 用户词典 | bundle 内 rime-data + 用户配置下拉 |
| 用户词库 | AppGroup/Rime（若签名团队配了 groups）或各自私有（无 AppGroup 互不相通） | `~/Library/Rime` | AppGroup | AppGroup |

**Quill 独有**：因为 iOS 扩展 `~77MB` 内存红线 `deploy` 会被 kill，只能「零生成」读预建 `.bin`。三方都选择了「主 App 内存里跑部署」，Quill 是唯一「运行时零生成」的。

---

## 4. 深浅色与键盘配色

### 深浅色决策（本次改动主题）
| 项目 | 机制 | 复杂度 |
|---|---|---|
| Quill（现） | `@Environment(\.colorScheme)` 纯 SwiftUI，controller 不再解析 dark/light；之前 `resolvedIsDark()` 三级兜底（keyboardAppearance→trait→UIScreen）已移除 | 最简 |
| Squirrel | `NSApp.effectiveAppearance`（跟随系统），面板配色由 scheme 提供 | 低（桌面天然同步） |
| Hamster | `KeyboardContext.hasDarkColorScheme` = trait；`sync(with:)` 更新，并兼容「host dark 但扩展仍 light」的 iOS bug 场景 | 中 |
| fcitx5-ios | 同 Quill：`.dark ? 深版 : 亮版`，view 内 `@Environment(\.colorScheme)` 自动跟随 | 最简 |

### 键帽配色
- **Quill**：键帽纯色块，`Theme` 提供 base colors；深色 = 半透明叠加（alpha 由 `overlay(base:target:)` 从背板常量与目标灰反解），贴合 fcitx5-ios 风格；按压单一 `pressedKeyBackground` tone。confirm 键 `#007AFF`；候选选中 pill。无渐变/阴影/描边。
- **Squirrel**：桌面无「键帽」，候选面板由用户挑 `color_scheme` 预存（原生支持 `preset_color_schemes`）。
- **Hamster**：`buttonBackgroundColorForStyle`（样式态/按下态区分）+ 自定义主题、键帽字体颜色、圆角。
- **fcitx5-ios**：key cap 用「深浅色两套 + 半透明叠加 blend」参数，高亮 `#007AFF`。有 `blend` 帮助函数。

---

## 5. 候选栏与用户界面

| 项目 | 候选条 | 展开 |
|---|---|---|
| Quill | 横向候选条 panel（>9 候选分页） | 点击 Chevron → 全屏网格（对齐首项）+ 再次点击收起 |
| Squirrel | 浮动候选窗口（自绘） | 窗口内翻页 |
| Hamster | 水平工具栏 候选条 | 「…」/滑动翻页（`CandidatePagingView`） |
| fcitx5-ios | 横向 candidate bar（懒加载） | 「expand」+ 页面网格 + 备注（click/backspace 行操作） |

Quill 的展开网格是对 Hamster/fcitx5 的仿：「chevron 从候选栏挑出全部候选进入大网格」。

---

## 6. 同步 / 云

| 项目 | 方式 | 手动/自动 |
|---|---|---|
| Quill | WebDAV（候选栏左侧菜单 → 同步页，仅键盘侧触发）本地暂存 staging temp（`tmp/RimeSyncStage`），上传各设备目录 | **手动**（同步页按钮） |
| Squirrel | `rime_sync_user_data` / 可同步 `~/Library/Rime/sync` / WebDAV 用户方案 | 自动或手动（`Sync` 菜单） |
| Hamster | iCloud（CloudKit）+ `syncDirDictionary` | 自动 |
| fcitx5-ios | AppGroup + 局域网 HTTP（`32489` / Swifter）+ magic text | （用户可按 mail 手动） |

Quill 是唯一「无云、需用户主动网络」的。

---

## 7. 交互与手势

- **Quill**：tap、空格双击句号、shift 双击锁 Caps（0.35s）、键盘预览 bubble、按压色。
- **Hamster**：完整 Key 手势（double tap / long press / repeat / drag / swipe 帧阈值）。
- **fcitx5-ios**：`KeyGesture` tap / double / long / swipe-up（候选）/ swipe-down / slide（退格 repeat）等整套。

Quill 目前只实现 bubble + tap 按压，没有 drag/swipe/长按连续退格等。

---

## 8. 工程 / 调试对比

| | 构建方式 | 包管理 | 测试 | 数据生成 |
|---|---|---|---|---|
| Quill | xcodebuild + SwiftPM | xcodegen project.yml | swift-testing / XCTest（候选网格、行布局、主题已测） | scripts/build-prebuilt-data.sh |
| Squirrel | Xcode + Makefile | — | XCTest 少量 | 构建脚本内 deploy |
| Hamster | 6 个包 + Xcode | SPM | 少量 | `InputSchemaBuild.sh` |
| fcitx5-ios | CMake + ios-cmake + 子模块 | C++ 子模块 | — | install-deps + deploy |

Quill 的特点是 librime 用**预编译 xcframework**（`Frameworks/`），其余三家都源码/子模块 build。

---

## 9. 结论 / 对我们可借鉴

1. **主 App 做真部署 + AppGroup 数据共享**（Hamster / fcitx5 共同模式）：规避扩展内存限制。Quill 若未来真机放宽，可做成「主 App Deploy ⇒ 预交付 build/」外推。
2. **AppGroup 数据互通**：Quill 无 AppGroup 时键盘与 App 各自私有、互不相通，这是痛点。
3. **可扩展配置模式**：fcitx5-ios 的 uipanel、Hamster 的配色/字体都可作为「若 Quill 要开放主题时」的 API 蓝本。
4. **候选懒加载 + 滑动**：Quill 展开当前全量渲染，fcitx5-ios list 用懒加载需量化热点。

---

*2026-08 Quill 仓库内核对。*