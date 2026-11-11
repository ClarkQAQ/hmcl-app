#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$project_dir/release.env"
source "$project_dir/scripts/common.sh"

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || fail '请在 Apple Silicon Mac 上原生运行构建脚本。'
xcrun --sdk macosx --find clang > /dev/null ||
    fail '请先安装 Xcode 命令行工具（xcode-select --install）。'

dist="$project_dir/dist"
mkdir -p "$dist"
stage=$(mktemp -d "$dist/.build.XXXXXXXX")
trap 'rm -r -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

app="$stage/HMCL.app"
contents="$app/Contents"
resources="$contents/Resources"
launcher="$contents/MacOS/HMCL"
runtime="$contents/$runtime_bundle"
runtime_contents="$runtime/Contents"
runtime_home="$runtime_contents/Home"
jar="$resources/HMCL.jar"

mkdir -p "$contents/MacOS" "$resources/Licenses" "$runtime_contents/MacOS" "$runtime_home"
xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=11.0 -O2 -fobjc-arc -Wall -Wextra \
    -framework Foundation -framework AppKit "$project_dir/launcher.m" -o "$launcher"
xcrun --sdk macosx clang -arch arm64 -O2 -Wall -Wextra "$project_dir/publish-app.c" -o "$stage/publish-app"

download "$hmcl_url" "$jar" "$hmcl_sha256"
download "$runtime_url" "$stage/runtime.tar.gz" "$runtime_sha256"
tar -xzf "$stage/runtime.tar.gz" --strip-components 1 -C "$runtime_home"
[[ -s "$runtime_home/LICENSE" && -d "$runtime_home/legal" ]] || fail 'Java 运行时许可证缺失。'
cp "$runtime_home/lib/libjli.dylib" "$runtime_contents/MacOS/libjli.dylib"
download "$hmcl_license_url" "$resources/Licenses/HMCL-LICENSE.txt" "$hmcl_license_sha256"
download "$hmcl_terms_url" "$stage/hmcl-readme.md" "$hmcl_terms_sha256"
awk '/^## 开源协议[[:space:]]*$/ { terms = 1 }
    terms && /^## / && !/^## 开源协议[[:space:]]*$/ { exit }
    terms { print }' "$stage/hmcl-readme.md" > "$resources/Licenses/HMCL-Additional-Terms.md"
[[ -s "$resources/Licenses/HMCL-Additional-Terms.md" ]] || fail 'HMCL 附加条款缺失。'

cat > "$runtime_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.hmcl.app.runtime</string>
    <key>CFBundleName</key>
    <string>Java Runtime</string>
    <key>CFBundleExecutable</key>
    <string>libjli.dylib</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
</dict>
</plist>
PLIST

cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.hmcl.app</string>
    <key>CFBundleName</key>
    <string>HMCL</string>
    <key>CFBundleExecutable</key>
    <string>HMCL</string>
    <key>CFBundleIconFile</key>
    <string>HMCL.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$hmcl_version</string>
    <key>CFBundleVersion</key>
    <string>$hmcl_version</string>
    <key>HMCLPackageVersion</key>
    <string>${hmcl_version}-r${revision}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.games</string>
</dict>
</plist>
EOF

# HMCL 的更新协议需要 SHA-1 字段。下载校验使用上面的官方 SHA-256。
jar_sha1=$(shasum -a 1 < "$jar")
cat > "$resources/update.json" <<EOF
{
    "version": "$hmcl_version",
    "jar": "$hmcl_url",
    "jarsha1": "${jar_sha1%% *}",
    "force": false
}
EOF

unzip -p "$jar" assets/img/icon-mac.png > "$stage/icon.png"
iconset="$stage/HMCL.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$stage/icon.png" --out "$iconset/icon_${size}x${size}.png" > /dev/null
    if (( size < 512 )); then
        pixels=$((size * 2))
        sips -z "$pixels" "$pixels" "$stage/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
    fi
done
iconutil -c icns -o "$resources/HMCL.icns" "$iconset"

codesign --force --sign - "$runtime"
codesign --sign - "$app"
verify_app "$app"
"$stage/publish-app" "$app" "$dist/HMCL.app"
printf '构建完成：%s\n' "$dist/HMCL.app"
