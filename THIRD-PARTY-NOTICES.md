# Third-Party Notices

This project bundles prebuilt binaries and RIME data under their own licenses.
The app source code itself is MIT licensed (see `LICENSE`). Unless noted
otherwise, each entry's full license text is available at the linked upstream
source and at the canonical SPDX link listed in
[License references](#license-references).

## Compiled into `Frameworks/*.xcframework`

Static libraries cross-compiled for iOS by `scripts/build-librime.sh` from the
[RIME project](https://github.com/rime) toolchain and vendored as xcframeworks.

| Component | Version | License | Copyright |
|---|---|---|---|
| [librime](https://github.com/rime/librime) | 1.16.0 | BSD-3-Clause | RIME Developers |
| [boost](https://www.boost.org/) (filesystem, regex, atomic) | 1.89.0 | Boost Software License 1.0 | Boost Authors |
| [glog](https://github.com/google/glog) | v0.7.1 | BSD-3-Clause | Google |
| [leveldb](https://github.com/google/leveldb) | 1.23 | BSD-3-Clause | Google |
| [marisa-trie](https://github.com/s-yata/marisa-trie) | v0.3.1 | BSD-2-Clause OR LGPL-2.1-or-later | Susumu Yata |
| [OpenCC](https://github.com/BYVoid/OpenCC) | ver.1.1.9 | Apache-2.0 | OpenCC Contributors |
| [yaml-cpp](https://github.com/jbeder/yaml-cpp) | 0.8.0 | MIT | Jesse Beder |

The librime build merges these plugins (`BUILD_MERGED_PLUGINS=ON`):

| Plugin | Version | License | Copyright |
|---|---|---|---|
| [librime-lua](https://github.com/rime/librime-lua) (with in-tree Lua 5.4.8) | Squirrel 1.1.2 baseline (`68f9c36`) | BSD-3-Clause | librime-lua Developers |
| Lua | 5.4.8 | MIT | PUC-Rio |
| [librime-octagram](https://github.com/rime/librime-octagram) | Squirrel 1.1.2 baseline (`dfcc151`) | BSD-3-Clause | RIME Developers |

## RIME data in `Resources/SharedSupport/`

RIME for iOS reads prebuilt data from `Resources/SharedSupport/build/` and the
bundled source files. Most files are copied verbatim from upstream and must
track those sources (see AGENTS.md and docs/dependencies.md); attribution is therefore per source.

| Content | Source | License |
|---|---|---|
| `default.yaml`, `symbols.yaml`, `essay.txt` | [librime](https://github.com/rime/librime) `data/minimal` (as shipped by squirrel 1.1.2; `default.yaml` carries two RIME for iOS edits: `schema_list` and `menu.page_size`) | BSD-3-Clause |
| `luna_pinyin.schema.yaml`, `luna_pinyin.dict.yaml`, `luna_pinyin_simp.schema.yaml`, `pinyin.yaml` | [rime-luna-pinyin](https://github.com/rime/rime-luna-pinyin) | LGPL-3.0 |
| `opencc/` (conversion data) | [OpenCC](https://github.com/BYVoid/OpenCC) ver.1.1.9 | Apache-2.0 |
| `cn_dicts/`, `en_dicts/`, `lua/`, `lm_sc.gram`, `melt_eng.*`, `luna_pinyin_extended.dict.yaml`, `japanese.*`, `default.custom.yaml`, `luna_pinyin.custom.yaml`, `squirrel.custom.yaml`, `weasel.custom.yaml`, `ibus_rime.custom.yaml` | [qvshuo/luna-pinyin-enhanced](https://github.com/qvshuo/luna-pinyin-enhanced) (formerly qvshuo/squirrel) | GPL-3.0 |

Notes on the aggregated qvshuo data (per its README):

- `cn_dicts/` is curated from the core dictionaries of
  [Blossom Rime](https://github.com/gaboolic/rime-frost) (白霜拼音) and
  fcitx5-pinyin-zhwiki.
- `en_dicts/`, `melt_eng.*` and `lua/reduce_english_filter.lua` come from
  [rime-ice](https://github.com/iDvel/rime-ice) (雾凇拼音), GPL-3.0.
- `lm_sc.gram` is the pinyin language model from
  [fcitx5-chinese-addons](https://github.com/fcitx/fcitx5-chinese-addons),
  LGPL-2.1-or-later.
- **All `japanese.*` files** belong to the luna-pinyin-enhanced repo, synced
  verbatim from [gkovacs/rime-japanese](https://github.com/gkovacs/rime-japanese);
  that repo is their essential source. `japanese.mozc.dict.yaml` and
  `japanese.jmdict.dict.yaml` are conversions of [mozc](https://github.com/google/mozc)
  (BSD-3-Clause) and [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html)
  (CC BY-SA 4.0, EDRDG licence) data respectively, so those data licenses still
  apply.
- `default.custom.yaml`, `luna_pinyin.custom.yaml` and the desktop-only
  `squirrel.custom.yaml` / `weasel.custom.yaml` / `ibus_rime.custom.yaml`
  patches are copied **verbatim** from luna-pinyin-enhanced (not RIME for iOS-authored).

## License references

| License | Canonical text |
|---|---|
| BSD-2-Clause | <https://opensource.org/license/bsd-2-clause> |
| BSD-3-Clause | <https://opensource.org/license/bsd-3-clause> |
| MIT | <https://opensource.org/license/mit> |
| Apache-2.0 | <https://www.apache.org/licenses/LICENSE-2.0> |
| Boost Software License 1.0 | <https://www.boost.org/LICENSE_1_0.txt> |
| LGPL-2.1-or-later | <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html> |
| LGPL-3.0 | <https://www.gnu.org/licenses/lgpl-3.0.html> |
| GPL-3.0 | <https://www.gnu.org/licenses/gpl-3.0.html> |
| CC BY-SA 4.0 | <https://creativecommons.org/licenses/by-sa/4.0/> |
| EDRDG licence | <https://www.edrdg.org/edrdg/licence.html> |