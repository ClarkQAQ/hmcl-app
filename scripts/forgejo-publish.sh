#!/bin/bash
set -euo pipefail
export LC_ALL=C

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ $# == 1 ]] || fail '用法：scripts/forgejo-publish.sh vX.Y.Z-rN'
tag=$1
github_repo=${GITHUB_RELEASE_REPO:-ClarkQAQ/hmcl-app}
forgejo_url=${FORGEJO_SERVER_URL:?需要 FORGEJO_SERVER_URL}
forgejo_owner=${FORGEJO_REPOSITORY_OWNER:?需要 FORGEJO_REPOSITORY_OWNER}
token=${FORGEJO_PACKAGE_TOKEN:?请配置 Actions Secret HMCL_PACKAGE_TOKEN}
forgejo_auth="Authorization: token $token"

[[ $tag =~ ^v[0-9]+(\.[0-9]+){2}-r[1-9][0-9]*$ ]] || fail '标签必须使用 vX.Y.Z-rN 格式。'
[[ $github_repo =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ ]] || fail 'GitHub 仓库必须使用 owner/repo 格式。'
[[ $forgejo_owner =~ ^[A-Za-z0-9_.-]+$ ]] || fail 'Forgejo 软件包所有者无效。'
for command in git curl jq shasum cmp sort; do
    command -v "$command" >/dev/null || fail "Forgejo runner 缺少 ${command}。"
done

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$project_dir"
# shellcheck source=../release.env
source ./release.env

[[ $runtime_version =~ ^[0-9]+(\.[0-9]+)+\+[0-9]+$ ]] || fail 'release.env 的 Liberica 版本格式无效。'
[[ $hmcl_source_sha256 =~ ^[0-9a-f]{64}$ && $runtime_source_sha256 =~ ^[0-9a-f]{64}$ ]] ||
    fail 'release.env 必须锁定 HMCL 和 Liberica 源码归档的 SHA-256。'
version="${hmcl_version}-r${revision}"
[[ $tag == "v$version" ]] || fail "Forgejo 标签 $tag 与 release.env 不一致，应为 v${version}。"
tag_ref="refs/tags/$tag"
commit=$(git rev-parse HEAD)
tag_commit=$(git rev-parse --verify "$tag_ref^{commit}")
[[ $commit == "$tag_commit" ]] || fail "当前检出提交与 Forgejo 标签 $tag 不一致。"

artifact="HMCL-macOS-${version}-arm64"
hmcl_source="HMCL-$hmcl_version-sources.tar.gz"
runtime_source="Liberica-${runtime_version//+/-b}-sources.tar.gz"
payload_files=("$artifact.dmg" "$artifact.zip" "$hmcl_source" "$runtime_source" release.json)
files=("${payload_files[@]}" SHA256SUMS)
expected_assets=$(jq -n --args '$ARGS.positional' "${files[@]}")

stage=$(mktemp -d "${TMPDIR:-/tmp}/hmcl-forgejo.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$stage"

https_curl() {
    curl -q --silent --show-error --connect-timeout 15 --retry 2 \
        --proto '=https' --proto-redir '=https' "$@"
}

release_api="https://api.github.com/repos/$github_repo/releases/tags/$tag"
printf '等待 GitHub 发布 %s %s。\n' "$github_repo" "$tag"
deadline=$((SECONDS + 900))
while :; do
    status=$(https_curl --max-time 30 --output github-release.json --write-out '%{http_code}' \
        --header 'Accept: application/vnd.github+json' "$release_api")
    case "$status" in
        200)
            jq -e --arg tag "$tag" '.tag_name == $tag' github-release.json >/dev/null ||
                fail 'GitHub Release API 返回的标签与请求不一致。'
            if jq -e --argjson expected "$expected_assets" '
                [.assets[] | select(.state == "uploaded") | .name] as $uploaded
                | .draft == false and .prerelease == false and (($expected - $uploaded) | length == 0)
            ' github-release.json >/dev/null; then
                break
            fi
            ;;
        404) ;;
        *) fail "读取 GitHub Release 失败，HTTP ${status}。" ;;
    esac
    (( SECONDS < deadline )) || fail "等待 GitHub 发布 $tag 超时。发布完成后可手动重跑。"
    sleep 30
done

github_refs=$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    ls-remote --tags "https://github.com/$github_repo.git" "$tag_ref" "$tag_ref^{}")
github_commit=$(awk -v ref="$tag_ref" '
    $2 == ref { tag = $1 }
    $2 == ref "^{}" { commit = $1 }
    END { print (commit == "" ? tag : commit) }
' <<< "$github_refs")
[[ $github_commit == "$commit" ]] || fail "GitHub 与 Forgejo 的 $tag 标签指向不同提交。"

for file in "${files[@]}"; do
    printf '下载 %s。\n' "$file"
    https_curl --fail --location --max-redirs 5 --max-time 600 --output "$file" \
        "https://github.com/$github_repo/releases/download/$tag/$file"
done

jq -e --arg tag "$tag" --arg commit "$commit" --arg hmcl "$hmcl_version" \
    --arg runtime_vendor "$runtime_vendor" --arg runtime_version "$runtime_version" \
    --arg java "$java_version" --arg javafx "$javafx_version" '
    .tag == $tag and .commit == $commit and .hmcl_version == $hmcl
    and .runtime_vendor == $runtime_vendor and .runtime_version == $runtime_version
    and .java_version == $java and .javafx_version == $javafx and .architecture == "arm64"
    and .signing == "ad-hoc"
' release.json >/dev/null || fail 'release.json 与当前标签、提交或 release.env 不一致。'

shasum -a 256 "${payload_files[@]}" > calculated-checksums
cmp -s <(sort calculated-checksums) <(sort SHA256SUMS) ||
    fail 'SHA256SUMS 与发布文件不一致。'
grep -Fxq "$hmcl_source_sha256  $hmcl_source" calculated-checksums ||
    fail 'HMCL 源码归档的 SHA-256 与 release.env 不一致。'
grep -Fxq "$runtime_source_sha256  $runtime_source" calculated-checksums ||
    fail 'Liberica 源码归档的 SHA-256 与 release.env 不一致。'
shasum -a 256 SHA256SUMS >> calculated-checksums

package_path="$forgejo_owner/generic/hmcl-app/$version"
package_api="${forgejo_url%/}/api/v1/packages/$package_path/files"
package_upload="${forgejo_url%/}/api/packages/$package_path"

read_package_files() {
    local status
    status=$(https_curl --max-time 30 --output package-files.json --write-out '%{http_code}' \
        --header @- "$package_api" <<< "$forgejo_auth")
    case "$status" in
        200) jq -e 'type == "array" and all(.[]; (.sha256 | test("^[0-9a-f]{64}$")))' \
                package-files.json >/dev/null || fail 'Forgejo 返回的文件摘要无效。' ;;
        404) printf '[]\n' > package-files.json ;;
        *) fail "读取 Forgejo 软件包文件失败，HTTP ${status}。" ;;
    esac
}

package_hash() {
    jq -er --arg file "$1" '
        [.[] | select(.name == $file)]
        | if length == 0 then "" elif length == 1 then .[0].sha256 else error("重复的包文件") end
    ' package-files.json
}

read_package_files
while read -r expected_hash file; do
    existing_hash=$(package_hash "$file")
    [[ -z $existing_hash || $existing_hash == "$expected_hash" ]] ||
        fail "Forgejo 中的 $file 已存在，SHA-256 不一致。"
done < calculated-checksums

while read -r expected_hash file; do
    existing_hash=$(package_hash "$file")
    if [[ $existing_hash == "$expected_hash" ]]; then
        printf '已发布且 SHA-256 一致，跳过 %s。\n' "$file"
        continue
    fi

    printf '上传 %s。\n' "$file"
    status=$(https_curl --max-time 600 --output upload-response --write-out '%{http_code}' \
        --header @- --upload-file "$file" "$package_upload/$file" <<< "$forgejo_auth")
    case "$status" in
        201) ;;
        409)
            read_package_files
            [[ $(package_hash "$file") == "$expected_hash" ]] ||
                fail "Forgejo 中的 $file 已存在，SHA-256 不一致。"
            ;;
        *) fail "上传 $file 失败，HTTP ${status}。" ;;
    esac
done < calculated-checksums

read_package_files
while read -r expected_hash file; do
    [[ $(package_hash "$file") == "$expected_hash" ]] || fail "Forgejo 软件包的 $file 摘要校验失败。"
done < calculated-checksums

printf 'Forgejo 软件包 hmcl-app/%s 已发布并验证。\n' "$version"
