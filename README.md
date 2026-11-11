# HMCL.app 适用于 Apple 芯片 Mac

应用内置 Hello Minecraft! Launcher 3.16.4 和 Azul Zulu 21.54.109 CA JRE FX（Java 21.0.13.0.3，含 JavaFX 23.0.9+102）。启动 HMCL 无需预先安装 Java 或 JavaFX。

## 下载与安装

公开发布时，GitHub Release 和 Forgejo 的 `hmcl-app` 软件包会提供同一批文件。DMG 和 ZIP 内含同一应用，任选一种安装。 [GitHub Releases](https://github.com/ClarkQAQ/hmcl-app/releases) · [Forgejo Packages](https://forgejo.gulugulu.moe/clark/-/packages)

1. 下载 `arm64` 的 DMG 或 ZIP 及同版本的 `SHA256SUMS`。把两个文件放到同一目录，运行 `shasum -a 256 --check --ignore-missing SHA256SUMS`，确认所下载的安装包显示 `OK`。
2. 打开 DMG 后，把 `HMCL.app` 拖入“应用程序”。使用 ZIP 时，先解压，再将 `HMCL.app` 移到“应用程序”。
3. 双击 `HMCL.app`。应用采用临时签名（ad hoc）。首次启动若被 macOS 拦截，在确认来源和校验值后，打开“系统设置 → 隐私与安全性”，找到 HMCL 的提示并点按“仍要打开”。 [Apple 支持](https://support.apple.com/zh-cn/102445)

## 本地构建

需要 Apple 芯片 Mac、Xcode 或 Xcode Command Line Tools，以及可访问 GitHub 和 Azul 的网络。可用 `xcode-select --install` 安装命令行工具。在项目目录构建并打开应用。

```sh
./build.sh
open dist/HMCL.app
```

运行 `./package.sh` 可同时构建和验证 DMG 与 ZIP。当前版本在 `dist/` 生成以下文件。

- `HMCL-macOS-3.16.4-r1-arm64.dmg`
- `HMCL-macOS-3.16.4-r1-arm64.zip`
- `SHA256SUMS` 和 `release.json`。未使用 Git 或工作区有未提交的改动时，清单中的 `commit` 为 `null`。

脚本从上游官方地址下载 HMCL JAR 和 Azul 运行时，按 SHA-256 校验后打包。登录账户、下载游戏等 HMCL 功能仍使用各自的在线服务。

## 数据目录

- HMCL 工作目录为 `~/Library/Application Support/hmcl`。默认工作区设置位于其中的 `.hmcl/config`，启动日志位于 `.hmcl/logs`。
- 默认游戏目录为“当前文件夹”，对应 `~/Library/Application Support/hmcl/.minecraft`。也可选择“官方启动器文件夹”来使用 `~/Library/Application Support/minecraft`，或添加自定义目录。
- 存档位于所选游戏目录下的 `saves/`。开启版本隔离的实例使用 `versions/<实例名>/saves/`。 [HMCL 版本隔离说明](https://docs.hmcl.net/launcher/set-item-details.html)

## 更新应用

HMCL 的更新检查使用包内的同版本元数据。升级时先退出 HMCL，再用新版 `HMCL.app` 整体替换旧应用。配置、日志和游戏存档位于应用包外。

自行构建新版时，在 `release.env` 中同步更新依赖版本、下载地址和 SHA-256。发布标签为 `v<HMCL 版本>-r<修订号>`。HMCL 升级时从 `r1` 开始。同一 HMCL 版本的打包或运行时更新递增修订号。 [HMCL 官方发布](https://github.com/HMCL-dev/HMCL/releases) · [Azul Metadata API](https://docs.azul.com/core/install/metadata-api)

## 公开发布

公开打包需要为内置 Zulu 构建提供对应的 OpenJDK 和 OpenJFX 源码归档。当前 `release.env` 的 `zulu_source_url` 和 `zulu_source_sha256` 待填。可向 `azul_openjdk@azul.com` 索取 `zulu21.54.109-ca-fx-jre21.0.13.0.3-macosx_aarch64.tar.gz` 对应的源码，并附上运行时 `Contents/Home/readme.txt` 中的版本代码 `Zulu 21.54+109 76341639-adf6-4948-8f1c-b7049b2dab70`。取得源码后，将公开可下载的 `.tar.gz` HTTPS 地址及其 SHA-256 写入 `release.env`。 [Azul OpenJDK 许可说明](https://docs.azul.com/core/tpls/october-2026/zulu21_jdk_tpl.html) · [Azul JavaFX 许可说明](https://docs.azul.com/core/tpls/october-2026/zulu21_jfx_tpl.html)

Forgejo 需要启用 Actions 和 Packages，将具有 `write:package` 权限的 `clark` 访问令牌配置为 Actions Secret `HMCL_PACKAGE_TOKEN`。工作流默认使用标记为 `ubuntu-latest` 的 Linux runner，可通过 Actions 变量 `HMCL_PUBLISH_RUNNER` 指定其他标记。runner 需提供 Node.js 20、Bash、`curl`、`jq`、`git` 和 `shasum`。 [Forgejo Generic Package Registry](https://forgejo.org/docs/latest/user/packages/generic/)

1. 将包含工作流和 `release.env` 的 `main` 分别推到 `github` 和 `forgejo`。首次推送后确认两端默认分支均为 `main`。在干净工作区为该提交创建匹配的标签，例如 `git tag v3.16.4-r1`。如需本地验证发布包，在 Apple 芯片 Mac 上运行 `./package.sh --release`。
2. 先运行 `git push github v3.16.4-r1`。GitHub Actions 构建并校验 DMG、ZIP、`SHA256SUMS`、`release.json`、HMCL 源码包和 Zulu 源码包，全部通过后公开 Release。
3. 等 GitHub Release 公开后，运行 `git push forgejo v3.16.4-r1`。Forgejo 校验提交和附件，将同一批文件镜像到 `hmcl-app` Generic Package 的 `3.16.4-r1` 版本。需要手动补跑时，在 Forgejo Actions 中运行 `Mirror release to Forgejo Packages`，填写 `tag` 为 `v3.16.4-r1`。

## 上游与类似项目

- HMCL JAR 和 Zulu JRE FX 来自各自官方发布。上游包自带的许可证和声明随应用保留。 [HMCL 3.16.4](https://github.com/HMCL-dev/HMCL/releases/tag/v3.16.4) · [Zulu 21.54.109 ARM64 构建元数据](https://api.azul.com/metadata/v1/zulu/packages/80d2f010-dcd8-4d15-b6ab-84915ee52783)
- `SomeoneHX/hmcl-mac-builder` 可以把官方 HMCL 和构建机上指定的 Java 运行时一起打进 macOS `.app`。 [hmcl-mac-builder](https://github.com/SomeoneHX/hmcl-mac-builder)
- `yznn007/HMCL-macOS` 和 `dragon-fish/HMCL-macOS` 提供依赖系统 Java 的 macOS 打包方案。`KSSJW/hmcl-full-runtime` 将 Zulu JRE FX 和 HMCL 一起打成 Linux AppImage。 [yznn007/HMCL-macOS](https://github.com/yznn007/HMCL-macOS#java-requirement) · [dragon-fish/HMCL-macOS](https://github.com/dragon-fish/HMCL-macOS) · [KSSJW/hmcl-full-runtime](https://github.com/KSSJW/hmcl-full-runtime#custom)
