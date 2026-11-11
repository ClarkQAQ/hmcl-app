# HMCL.app 适用于 Apple 芯片 Mac

应用内置 Hello Minecraft! Launcher 3.16.4 和 BellSoft Liberica Full JRE 21.0.13.0.3+5（Java 21.0.13.0.3，含 JavaFX 21.0.13+1）。启动 HMCL 无需预先安装 Java 或 JavaFX。

## 下载与安装

GitHub Releases 提供公开下载。拥有 `gulugulu` 组织访问权限的用户也可在 Forgejo 下载同一批文件。DMG 和 ZIP 内含同一应用，任选一种安装。 [GitHub Releases](https://github.com/ClarkQAQ/hmcl-app/releases) · [Forgejo Packages](https://forgejo.gulugulu.moe/gulugulu/-/packages)

1. 下载 `arm64` 的 DMG 或 ZIP 及同版本的 `SHA256SUMS`。把两个文件放到同一目录，运行 `shasum -a 256 --check --ignore-missing SHA256SUMS`，确认所下载的安装包显示 `OK`。
2. 打开 DMG 后，把 `HMCL.app` 拖入“应用程序”。使用 ZIP 时，先解压，再将 `HMCL.app` 移到“应用程序”。
3. 双击 `HMCL.app`。应用采用临时签名（ad hoc）。首次启动若被 macOS 拦截，在确认来源和校验值后，打开“系统设置 → 隐私与安全性”，找到 HMCL 的提示并点按“仍要打开”。 [Apple 支持](https://support.apple.com/zh-cn/102445)

## 本地构建

需要 Apple 芯片 Mac、Xcode 或 Xcode Command Line Tools，以及可访问 GitHub 的网络。可用 `xcode-select --install` 安装命令行工具。在项目目录构建并打开应用。

```sh
./build.sh
open dist/HMCL.app
```

运行 `./package.sh` 可同时构建和验证 DMG 与 ZIP。当前版本在 `dist/` 生成以下文件。

- `HMCL-macOS-3.16.4-r2-arm64.dmg`
- `HMCL-macOS-3.16.4-r2-arm64.zip`
- `SHA256SUMS` 和 `release.json`。未使用 Git 或工作区有未提交的改动时，清单中的 `commit` 为 `null`。

脚本从上游官方地址下载 HMCL JAR 和 Liberica 运行时，按 SHA-256 校验后打包。登录账户、下载游戏等 HMCL 功能仍使用各自的在线服务。

## 数据目录

- HMCL 工作目录为 `~/Library/Application Support/hmcl`。默认工作区设置位于其中的 `.hmcl/config`，启动日志位于 `.hmcl/logs`。
- 默认游戏目录为“当前文件夹”，对应 `~/Library/Application Support/hmcl/.minecraft`。也可选择“官方启动器文件夹”来使用 `~/Library/Application Support/minecraft`，或添加自定义目录。
- 存档位于所选游戏目录下的 `saves/`。开启版本隔离的实例使用 `versions/<实例名>/saves/`。 [HMCL 版本隔离说明](https://docs.hmcl.net/launcher/set-item-details.html)

## 更新应用

HMCL 的更新检查使用包内的同版本元数据。升级时先退出 HMCL，再用新版 `HMCL.app` 整体替换旧应用。配置、日志和游戏存档位于应用包外。

自行构建新版时，在 `release.env` 中同步更新依赖版本、下载地址和 SHA-256。Liberica 运行时及其源码归档使用 `runtime_*` 字段。发布标签为 `v<HMCL 版本>-r<修订号>`。HMCL 升级时从 `r1` 开始。同一 HMCL 版本的打包或运行时更新递增修订号。 [HMCL 官方发布](https://github.com/HMCL-dev/HMCL/releases) · [BellSoft Liberica 官方发布](https://github.com/bell-sw/Liberica/releases)

## 公开发布

`./package.sh --release` 需要干净的工作区和与 `release.env` 匹配的标签。发布附件包含 HMCL 对应提交的源码归档，以及内置 JRE 对应的 Liberica Full 源码归档 `Liberica-21.0.13.0.3-b5-sources.tar.gz`。Liberica 的二进制和源码归档取自同一 BellSoft Release，脚本按 `release.env` 中的 SHA-256 校验下载。 [BellSoft Liberica 21.0.13.0.3+5](https://github.com/bell-sw/Liberica/releases/tag/21.0.13.0.3%2B5)

在 Forgejo 私有仓库 `gulugulu/hmcl-app` 启用 Actions 和 Packages。将有权向 `gulugulu` 组织发布软件包且具备 `write:package` 权限的个人访问令牌配置为 Actions Secret `HMCL_PACKAGE_TOKEN`。工作流默认使用标记为 `ubuntu-latest` 的 Linux runner，可通过 Actions 变量 `HMCL_PUBLISH_RUNNER` 指定其他标记。runner 需提供 Node.js 20、Bash、`curl`、`jq`、`git` 和 `shasum`。 [Forgejo Generic Package Registry](https://forgejo.org/docs/latest/user/packages/generic/)

1. 将包含工作流和 `release.env` 的 `main` 分别推到 `github` 和 `forgejo-private`。首次推送后确认两端默认分支均为 `main`。在干净工作区运行 `git tag v3.16.4-r2`，为该提交创建首发标签。如需本地验证发布包，在 Apple 芯片 Mac 上运行 `./package.sh --release`。
2. 先运行 `git push github v3.16.4-r2`。GitHub Actions 构建并校验 DMG、ZIP、`SHA256SUMS`、`release.json`、HMCL 源码包和 Liberica 源码包，全部通过后公开 Release。
3. 等 GitHub Release 公开后，运行 `git push forgejo-private v3.16.4-r2`。Forgejo 校验提交和附件，将同一批文件镜像到 `gulugulu` 组织下的 `hmcl-app` Generic Package，版本为 `3.16.4-r2`。需要手动补跑时，在 Forgejo Actions 中运行 `Mirror release to Forgejo Packages`，填写 `tag` 为 `v3.16.4-r2`。

## 上游与类似项目

- HMCL JAR 和 Liberica Full JRE 来自各自官方发布。上游包自带的许可证和声明随应用保留。 [HMCL 3.16.4](https://github.com/HMCL-dev/HMCL/releases/tag/v3.16.4) · [BellSoft Liberica 21.0.13.0.3+5](https://github.com/bell-sw/Liberica/releases/tag/21.0.13.0.3%2B5)
- `SomeoneHX/hmcl-mac-builder` 可以把官方 HMCL 和构建机上指定的 Java 运行时一起打进 macOS `.app`。 [hmcl-mac-builder](https://github.com/SomeoneHX/hmcl-mac-builder)
- `yznn007/HMCL-macOS` 和 `dragon-fish/HMCL-macOS` 提供依赖系统 Java 的 macOS 打包方案。`KSSJW/hmcl-full-runtime` 将 Zulu JRE FX 和 HMCL 一起打成 Linux AppImage。 [yznn007/HMCL-macOS](https://github.com/yznn007/HMCL-macOS#java-requirement) · [dragon-fish/HMCL-macOS](https://github.com/dragon-fish/HMCL-macOS) · [KSSJW/hmcl-full-runtime](https://github.com/KSSJW/hmcl-full-runtime#custom)
