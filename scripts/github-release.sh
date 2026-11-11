#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source ./release.env
source ./scripts/common.sh

tag="v${hmcl_version}-r${revision}"
[[ $tag =~ ^v[0-9]+(\.[0-9]+){2}-r[1-9][0-9]*$ ]] || fail "无效的发布标签：$tag"
[[ ${GITHUB_EVENT_NAME:-} == push && ${GITHUB_REF:-} == "refs/tags/$tag" ]] ||
    fail "只允许在推送标签 $tag 时发布。"
commit=$(git rev-parse HEAD)
[[ $(git rev-parse "${GITHUB_SHA:?}^{commit}") == "$commit" &&
    $(git rev-parse "refs/tags/$tag^{commit}") == "$commit" ]] ||
    fail "检出的提交与发布标签 $tag 不一致。"

repository=${GITHUB_REPOSITORY:?}
api="repos/$repository"
marker="<!-- hmcl-app release commit: $commit -->"
archive="HMCL-macOS-${hmcl_version}-r${revision}-arm64"
hmcl_source="HMCL-${hmcl_version}-sources.tar.gz"
runtime_source="Liberica-${runtime_version//+/-b}-sources.tar.gz"
payloads=("$archive.dmg" "$archive.zip" release.json
    "$hmcl_source" "$runtime_source")
assets=("${payloads[@]}" SHA256SUMS)
asset_names=$(printf '%s\n' "${assets[@]}" | LC_ALL=C sort)
state=$(mktemp -d)
trap 'rm -rf -- "$state"' EXIT

verify_remote_tag() {
    local object type sha
    object=$(gh api "$api/git/ref/tags/$tag" --jq '.object') || return 1
    while [[ $(jq -r .type <<< "$object") == tag ]]; do
        sha=$(jq -r .sha <<< "$object")
        object=$(gh api "$api/git/tags/$sha" --jq '.object') || return 1
    done
    type=$(jq -r .type <<< "$object")
    sha=$(jq -r .sha <<< "$object")
    [[ $type == commit && $sha == "$commit" ]] || fail "远端标签 $tag 未指向 ${commit}。"
}

find_release() {
    gh api --paginate --slurp "$api/releases?per_page=100" |
        jq --arg tag "$tag" '[.[][] | select(.tag_name == $tag)] |
            if length <= 1 then first // null else error("存在多个同名 Release") end'
}

verify_manifest() {
    jq -e --arg tag "$tag" --arg commit "$commit" --arg hmcl "$hmcl_version" \
        --arg vendor "$runtime_vendor" --arg runtime "$runtime_version" \
        --arg java "$java_version" --arg javafx "$javafx_version" '
        .tag == $tag and .commit == $commit and .hmcl_version == $hmcl and
        .runtime_vendor == $vendor and .runtime_version == $runtime and
        .java_version == $java and .javafx_version == $javafx and
        .architecture == "arm64" and .signing == "ad-hoc"' "$1" >/dev/null
}

verify_remote_assets() {
    local remote=$1 expected_checksums actual_checksums name id digest
    [[ $(jq -r '.[].name' <<< "$remote" | LC_ALL=C sort) == "$asset_names" ]] || return 1
    jq -e 'all(.[]; .state == "uploaded" and (.digest // "" | test("^sha256:[0-9a-f]{64}$")))' \
        <<< "$remote" >/dev/null || return 1
    jq -e --arg hmcl "$hmcl_source" --arg runtime "$runtime_source" \
        --arg hmcl_digest "sha256:$hmcl_source_sha256" --arg runtime_digest "sha256:$runtime_source_sha256" '
        any(.[]; .name == $hmcl and .digest == $hmcl_digest) and
        any(.[]; .name == $runtime and .digest == $runtime_digest)' <<< "$remote" >/dev/null || return 1

    for name in SHA256SUMS release.json; do
        id=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<< "$remote")
        digest=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .digest' <<< "$remote")
        gh api -H 'Accept: application/octet-stream' "$api/releases/assets/$id" > "$state/$name" || return 1
        [[ "sha256:$(sha256 "$state/$name")" == "$digest" ]] || return 1
    done

    expected_checksums=$(jq -r '.[] | select(.name != "SHA256SUMS") |
        "\(.digest | ltrimstr("sha256:"))  \(.name)"' <<< "$remote" | LC_ALL=C sort) || return 1
    actual_checksums=$(LC_ALL=C sort "$state/SHA256SUMS") || return 1
    [[ $actual_checksums == "$expected_checksums" ]] || return 1
    verify_manifest "$state/release.json"
}

verify_remote_tag
release=$(find_release)
if [[ $release != null ]]; then
    jq -e --arg marker "$marker" '.body | contains($marker)' <<< "$release" >/dev/null ||
        fail "现有 Release $tag 不属于此构建。"
    if [[ $(jq -r .draft <<< "$release") == false ]]; then
        verify_remote_assets "$(jq .assets <<< "$release")" || fail "已发布 Release $tag 的附件校验失败。"
        printf 'Release %s 已发布，附件校验通过。\n' "$tag"
        exit 0
    fi
fi

if [[ $release == null ]] || ! verify_remote_assets "$(jq .assets <<< "$release")"; then
    env -u GH_TOKEN -u GITHUB_TOKEN ./package.sh --release
    verify_manifest dist/release.json || fail '本地 release.json 与当前构建不一致。'
    local_checksums=$(cd dist && shasum -a 256 "${payloads[@]}" | LC_ALL=C sort)
    [[ $(LC_ALL=C sort dist/SHA256SUMS) == "$local_checksums" ]] || fail '本地发布附件校验失败。'
    verify_remote_tag

    if [[ $release == null ]]; then
        cat > "$state/notes" <<EOF
$marker

适用于 Apple 芯片 Mac。内置 HMCL ${hmcl_version}、${runtime_vendor} Liberica Full JRE ${runtime_version}（Java ${java_version}、JavaFX ${javafx_version}）。

应用使用临时签名（ad hoc），尚未经过 Apple 公证。DMG 和 ZIP 中包含相同的应用。

SHA256SUMS 记录应用包、构建信息和对应上游源码压缩包的校验值。
EOF
        gh release create "$tag" --repo "$repository" --verify-tag --draft \
            --title "HMCL for macOS $tag" --notes-file "$state/notes"
        release=$(find_release)
    fi

    release_id=$(jq -er --arg marker "$marker" \
        'select(.draft and (.body | contains($marker))) | .id' <<< "$release")
    remote=$(jq .assets <<< "$release")
    [[ -z $(LC_ALL=C comm -23 <(jq -r '.[].name' <<< "$remote" | LC_ALL=C sort) <(printf '%s\n' "$asset_names")) ]] ||
        fail "草稿 $tag 包含无法识别的附件。"

    for name in "${assets[@]}"; do
        digest=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .digest' <<< "$remote")
        local_digest="sha256:$(sha256 "dist/$name")"
        if [[ $digest == "$local_digest" ]]; then
            continue
        fi
        gh api "$api/releases/$release_id" | jq -e --arg marker "$marker" \
            '.draft and (.body | contains($marker))' >/dev/null || fail "Release $tag 已不再是此构建的草稿。"
        gh release upload "$tag" --repo "$repository" --clobber "dist/$name"
    done
fi

release=$(find_release)
jq -e --arg marker "$marker" '.draft and (.body | contains($marker))' <<< "$release" >/dev/null ||
    fail "Release $tag 已不再是此构建的草稿。"
verify_remote_assets "$(jq .assets <<< "$release")" || fail "草稿 $tag 的附件校验失败。"
verify_remote_tag
gh release edit "$tag" --repo "$repository" --verify-tag --draft=false
