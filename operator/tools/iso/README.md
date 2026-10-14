# iso — 等距解释图 / 动画（入口说明）

> **引擎、图、设计规范都在独立仓 `~/iso_flutter`**（框架包 `iso_engine` + 应用 `app`）。
> 本目录已不持有代码/规范：原 anatomy 的 JS kit 与 `references/` 已移入 `~/iso_flutter/docs/`。

对外工具：**`operator/tools/iso_native.sh`**（`render` / `anim` → 出图/动画 → 微信）。
它调用 `~/iso_flutter/bin/iso.sh` 生成文件，再由本仓 `wechat_send_file.sh` 发出——**本仓只做"调用 + 发微信"**。

- 图名 / 加图 / 构建：见 `~/iso_flutter/README.md`
- 图注册表：`~/iso_flutter/app/lib/main.dart` 的 `_figures`（`tmall-genie`(Lua) / `tmall-genie-dart`(Dart) / `lathe` / `tube`）
- 设计规范：`~/iso_flutter/docs/references/*.md`（craft/kit/motion…）
- 署名：anatomy（MIT）——见 `~/iso_flutter/docs/LICENSE-anatomy` 及 `iso_engine/lib/{*.dart,lua/*.lua}` 文件头
