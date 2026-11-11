#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$project_dir/release.env"
source "$project_dir/scripts/common.sh"

release=false
if (( $# == 1 )) && [[ $1 == --release ]]; then
    release=true
elif (( $# != 0 )); then
    fail '用法：./package.sh [--release]'
fi

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || fail '请在 Apple Silicon Mac 上原生运行打包脚本。'
[[ $hmcl_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $revision =~ ^[1-9][0-9]*$ ]] ||
    fail 'release.env 中的 HMCL 版本或打包修订无效。'

version="$hmcl_version-r$revision"
tag="v$version"
name="HMCL-macOS-$version-arm64"
commit=null
if head=$(git -C "$project_dir" rev-parse --verify HEAD 2>/dev/null) &&
    git_status=$(git -C "$project_dir" status --porcelain) && [[ -z $git_status ]]; then
    commit="\"$head\""
fi

if $release; then
    [[ $runtime_source_url == https://* && $runtime_source_sha256 =~ ^[0-9a-f]{64}$ ]] ||
        fail '公开发布需要在 release.env 中锁定对应的 OpenJDK 和 OpenJFX 源码归档。'
    tagged_commit=$(git -C "$project_dir" rev-parse --verify "refs/tags/$tag^{commit}" 2>/dev/null) ||
        fail "找不到发布标签 ${tag}。"
    [[ $commit == "\"$tagged_commit\"" ]] || fail "请从标签 $tag 对应的干净工作区打包。"
fi

dist="$project_dir/dist"
mkdir -p "$dist"
lock="$dist/.package.lock"
mkdir "$lock" 2>/dev/null || fail '已有打包任务在使用 dist。'
stage=
mounted=false

cleanup() {
    if $mounted && ! hdiutil detach "$stage/mounted" -quiet; then
        printf '无法卸载镜像，保留临时目录：%s\n' "$stage" >&2
        rmdir "$lock"
        return
    fi
    if [[ -n $stage ]]; then
        rm -r -- "$stage"
    fi
    rmdir "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stage=$(mktemp -d "$dist/.package.XXXXXXXX")

assets=("$name.dmg" "$name.zip" release.json)
if $release; then
    hmcl_source="HMCL-$hmcl_version-sources.tar.gz"
    runtime_source="Liberica-${runtime_version//+/-b}-sources.tar.gz"
    download "$hmcl_source_url" "$stage/$hmcl_source" "$hmcl_source_sha256"
    download "$runtime_source_url" "$stage/$runtime_source" "$runtime_source_sha256"
    tar -tzf "$stage/$hmcl_source" > /dev/null
    tar -tzf "$stage/$runtime_source" > /dev/null
    assets+=("$hmcl_source" "$runtime_source")
fi

"$project_dir/build.sh"

mkdir "$stage/image" "$stage/mounted" "$stage/unzipped"
ditto "$dist/HMCL.app" "$stage/image/HMCL.app"
ln -s /Applications "$stage/image/Applications"
ditto -c -k --sequesterRsrc --keepParent "$stage/image/HMCL.app" "$stage/$name.zip"
hdiutil create -quiet -format UDZO -fs HFS+ -volname HMCL \
    -srcfolder "$stage/image" "$stage/$name.dmg"

ditto -x -k "$stage/$name.zip" "$stage/unzipped"
verify_app "$stage/unzipped/HMCL.app"
hdiutil verify -quiet "$stage/$name.dmg"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/mounted" "$stage/$name.dmg"
mounted=true
[[ $(readlink "$stage/mounted/Applications") == /Applications ]] || fail 'DMG 缺少 Applications 链接。'
verify_app "$stage/mounted/HMCL.app"
hdiutil detach "$stage/mounted" -quiet
mounted=false

cat > "$stage/release.json" <<EOF
{
    "tag": "$tag",
    "commit": $commit,
    "hmcl_version": "$hmcl_version",
    "runtime_vendor": "$runtime_vendor",
    "runtime_version": "$runtime_version",
    "java_version": "$java_version",
    "javafx_version": "$javafx_version",
    "architecture": "arm64",
    "signing": "ad-hoc"
}
EOF
(
    cd "$stage"
    shasum -a 256 "${assets[@]}" > SHA256SUMS
)

for asset in "${assets[@]}" SHA256SUMS; do
    [[ ! -d $dist/$asset ]] || fail "输出路径已被目录占用：$dist/$asset"
done
for asset in "${assets[@]}" SHA256SUMS; do
    mv -f -- "$stage/$asset" "$dist/$asset"
done

printf '打包完成：%s\n' "$dist/$name.dmg" "$dist/$name.zip"
