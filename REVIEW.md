# 代码复审：RIME for iOS 2.0.0

本轮完成品牌、工程与模块更名，整理注释和核心测试，并根据最新 fcitx5-ios 与 Squirrel 正式版本重写[评估报告](docs/input-method-comparison.md)。没有引入多引擎、撤销历史或扩展内部署。

## 命名和结构

- 显示名统一为 RIME for iOS；工程和应用目标 RIMEForiOS，扩展 RIMEKeyboard。
- 物理目录 App、KeyboardExtension、Packages、Tests 按职责分开。Models/Sync 改为 KeyboardModels/RimeSync；测试由原来的 UITests 名称纠正为 RIMECoreTests，并按领域分组。
- 主应用视图 SetupView，宿主入口 KeyboardInputController，输入状态机 KeyboardInputModel，目录入口 RimePaths。C 插件桥改为 rime_ios_configure_modules / RimeEngineBridge.h。
- 新 bundle/App Group ID、目录、日志、诊断导出名、CI 产物和 RIME distribution 信息一致。设备默认 ID 改为 iPhone，不用产品名标识设备。
- 历史构建、旧引擎构建缓存、用户原始日志及旧生成 scheme 归档在工作区父级 archives/2026-10-01，原始日志字节内容未修改。历史 Git 提交及远端仓库地址不重写。英文词典中的正常单词继续按上游保留。

## 注释和测试

删去对显然代码的复述、重复架构说明和已废弃实现的描述。保留静态插件、C 指针生命期、一次性 commit、marked text 清理、引擎锁/取消、懒加载快照和内存上限等必要原因。平台内存数字改为历史观测，避免把某台设备结果描述成系统保证。

输入路由与布局重复情形合并为数据驱动检查；删除简单别名和固定提示文案断言。核心验证和取舍见 [testing.md](docs/testing.md)。未以删除测试来绕过功能错误。

## 安装和数据边界

新标识符会创建独立应用。旧私有词库、凭据无法自动跨容器读取；升级前先使用旧键盘同步，再配置新键盘并同步。两个设备应使用不同安装 ID。保留 librime 1.16.0 和上游字典数据；OpenCC 1.1.9 的两个切片重新编译，移除嵌入的旧构建目录，脚本使用 SHARE_INSTALL_PREFIX=SharedSupport，也不改变手动 WebDAV 协议。

## 验证

41 项核心测试通过（14 个 suite，原 69 项同类情形合并），iPhone Release 构建通过。新 bundle ID 在系统设置中成功添加，切换器选择及 4 项产品 UI 流程共 5 项临时宿主测试通过：混合预输入空格确认、候选展开/选择、同步草稿隔离、菜单、日志自动更新和分享关闭恢复。系统最近使用键盘确认为 art.anjing.rimeios.keyboard。主应用标题/启用状态/版本截图已核对；另采集真实扩展的深浅色候选截图更新 README。

本地生成 RIME-for-iOS-2.0.0-unsigned.ipa，检查 zip 完整性、应用/扩展标识、2.0.0（16）版本、扩展主类及预构建数据。验证记录在忽略的 build/review/2.0.0/。OpenCC 切片更新后重新通过 41 项核心测试和 Release 构建，并在实际扩展中复查深浅主题中文候选。模拟器为 iOS 26.5；mock 传输和模拟器不能替代自签真机、真实 WebDAV 和持续内存测量。
