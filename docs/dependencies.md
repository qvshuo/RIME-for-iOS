# 依赖与数据基线

核对日期：2026-10-01。Squirrel 最新正式版仍是 **1.1.2**。以该 tag 的 `action-install.sh`、librime 1.16.0 的 gitlink、构建 workflow 和实际发布包 `version-info.txt` 为依据，不以浮动 master 或最近的 tag 名代替提交。

| 组件 | 指定版本 / 提交 | 本项目结果 |
|---|---|---|
| librime | 1.16.0 / `a251145d` | 一致 |
| Boost | 1.89.0 | 与 librime 发布 workflow 一致 |
| glog | 0.7.1 / `7b134a5c` | 一致 |
| LevelDB | 1.23 / `99b3c03b` | 一致 |
| marisa-trie | 0.3.1 / `3e87d53b` | 一致 |
| OpenCC | 1.1.9 / `556ed224` | 一致；保留 iOS 禁用工具/数据生成的构建补丁 |
| yaml-cpp | 0.8.0 / `2f86d137` | 一致 |
| librime-lua | 发布包记录 `68f9c36` | 已从 `ec52e48` 调整到指定提交并重编译 |
| librime-octagram | 发布包记录 `dfcc151` | 已从 `bfb168c` 调整到指定提交并重编译 |
| Lua | Squirrel 构建未单独锁定 thirdparty 分支 | 本项目固定 5.4.8，保留 LUA_USE_IOS 构建定义 |
| GoogleTest、LevelDB 的 benchmark / GoogleTest | librime 与 LevelDB gitlink | 提交一致；未链接到发行应用 |
| librime-predict | 发布包记录 `920bd41` | 未引入；本项目没有该插件功能 |
| Sparkle | Squirrel 下载脚本指定 2.6.2 | macOS 更新器，不是本项目依赖 |
| plum | Squirrel gitlink `4c28f11f` | 桌面数据安装器，不是本项目运行依赖 |

依据：[Squirrel 下载脚本](https://github.com/rime/squirrel/blob/1.1.2/action-install.sh)、[librime macOS 构建](https://github.com/rime/librime/blob/1.16.0/.github/workflows/macos-build.yml)、[正式发布附件](https://github.com/rime/librime/releases/tag/1.16.0)。实际附件保存在工作区父目录 `reference-downloads/librime-1.16.0/`。

本轮重编译全部 9 个 xcframework 的 arm64 device / simulator 切片，使用 Xcode 27、iOS 27 SDK，最低目标仍为 iOS 26。完整源码提交与 18 个静态库 SHA-256 记录在 [Frameworks/versions.json](../Frameworks/versions.json)。构建使用独立源码 `/private/tmp/RIMEReleaseSources`。随后将默认 `../librime` 的插件源码对齐相同提交；原插件工作区（含未提交修改、暂存区及 Git 历史）完整保存到父目录 `archives/2026-10-01/pre-alignment-librime-lua` 和 `pre-alignment-librime-octagram`。OpenCC 构建补丁继续保留。

## 数据

增强词库逐文件同步到 qvshuo/luna-pinyin-enhanced `6bd91c9c129e710cc8360bb02d43fefea0c30225`（2026-09-27）。更新包括中文基础词、流行词、游戏词和英文词；不复制仓库 workflow、README 或隐藏维护文件。上游删除/收敛的词条保持其原样，不根据词条数量猜测版本新旧。

rime-luna-pinyin 最新 HEAD 仍为 `56b934b099dfbeab842320f13aa8b461a6ab3e42`；日语数据源仍为 `4c1e65135459175136f380e90ba52acb40fdfb2d`。`lm_sc.gram` 与增强库最新提交逐字节一致。OpenCC 配置和字典仍来自对应的 1.1.9 基线。所有受管理的数据保持上游原文，构建期重新生成 `SharedSupport/build/`；键盘内不部署。

## 重编译和验证

```sh
# 没有上游源码也可验证已提交的二进制。
./scripts/verify-dependencies.sh --binaries

# 独立源码须先检出 versions.json 中的全部提交，并准备 Boost/Lua 与 iOS 构建补丁。
RIME_ROOT=/path/to/pinned/librime ./scripts/verify-dependencies.sh
RIME_ROOT=/path/to/pinned/librime ./scripts/build-librime.sh

# 已有正确的 host 部署器时，仅重建数据。
./scripts/build-prebuilt-data.sh --deploy-only
```

引擎脚本在编译前检查源码提交，打包成功后记录二进制哈希。数据脚本在独立目录部署，校验关键输出后才替换旧数据；部署失败或目录替换被中断时恢复旧输出。`--package-only` 仅用于已经成功编译两种切片后的重新封装，不重新编译 C++。首次构建仍需完整执行脚本。

本地与发行 workflow 共用 `scripts/package-ipa.sh`。默认读取 `build/Release/` 的设备构建，也可传入应用路径和输出路径；检查应用/扩展版本、bundle ID、设备平台和未签名状态，验证 zip 后再替换 IPA。
