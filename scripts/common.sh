fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

sha256() {
    local digest
    digest=$(shasum -a 256 < "$1")
    printf '%s\n' "${digest%% *}"
}

download() {
    local url=$1 destination=$2 expected=$3
    printf '下载 %s\n' "${url##*/}"
    curl -q --fail --silent --show-error --location --retry 2 --connect-timeout 15 \
        --proto '=https' --proto-redir '=https' --output "$destination" "$url" ||
        fail "下载失败：$url"
    [[ $(sha256 "$destination") == "$expected" ]] || fail "SHA-256 校验失败：${url##*/}"
}

verify_app() {
    local app=$1 contents java java_info modules module
    contents="$app/Contents"
    java="$contents/PlugIns/ZuluJRE.jre/Contents/Home/bin/java"

    plutil -lint "$contents/Info.plist"
    [[ $(plutil -extract HMCLPackageVersion raw "$contents/Info.plist") == "${hmcl_version}-r${revision}" ]] ||
        fail "封装版本不匹配：$app"
    [[ $(lipo -archs "$contents/MacOS/HMCL") == arm64 ]] || fail '启动器不是 ARM64。'
    [[ $(lipo -archs "$java") == arm64 ]] || fail '内置 Java 不是 ARM64。'
    [[ $(sha256 "$contents/Resources/HMCL.jar") == "$hmcl_sha256" ]] || fail '内置 HMCL JAR 校验失败。'
    codesign --verify --deep --strict "$app"

    java_info=$("$java" -version 2>&1)
    [[ $java_info == *"\"$java_version\""* ]] || fail "内置 Java 版本应为 $java_version。"
    grep -Fxq "javafx.runtime.version=$javafx_version" "${java%/bin/java}/lib/javafx.properties" ||
        fail "内置 JavaFX 版本应为 $javafx_version。"
    modules=$("$java" --list-modules)
    for module in javafx.base javafx.controls javafx.fxml javafx.graphics javafx.media javafx.swing javafx.web; do
        [[ $'\n'$modules == *$'\n'"${module}@"* ]] || fail "内置运行时缺少 $module。"
    done
}
