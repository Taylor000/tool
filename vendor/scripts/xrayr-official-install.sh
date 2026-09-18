#!/usr/bin/env bash

set -o pipefail

FROZEN_VERSION="v0.9.4"
SELF_HOSTED_RELEASE_URL="https://raw.githubusercontent.com/Taylor000/XrayR/master/release/${FROZEN_VERSION}"
VENDOR_RAW_URL="https://raw.githubusercontent.com/Taylor000/tool/master/vendor/scripts"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"
MANAGER_FILE="/usr/bin/XrayR"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

info() {
    echo -e "${green}$*${plain}"
}

warn() {
    echo -e "${yellow}$*${plain}"
}

fail() {
    echo -e "${red}$*${plain}" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_dependencies() {
    local packages=(curl unzip ca-certificates coreutils)

    if command_exists apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get update &&
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    elif command_exists dnf; then
        dnf install -y "${packages[@]}"
    elif command_exists yum; then
        yum install -y "${packages[@]}"
    else
        fail "无法识别包管理器，请手动安装 curl、unzip、ca-certificates 和 coreutils。"
    fi
}

download_file() {
    local url=$1
    local destination=$2

    if command_exists curl; then
        curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 300 --retry 2 \
            "$url" -o "$destination"
    elif command_exists wget; then
        wget --https-only --quiet --timeout=300 --tries=3 \
            -O "$destination" "$url"
    else
        return 1
    fi
}

backup_file() {
    local path=$1

    if [[ -e "$path" && ! -d "$path" ]]; then
        cp -p "$path" "${path}.backup" || return 1
    fi
}

[[ $EUID -eq 0 ]] || fail "必须使用 root 用户运行此脚本。"
command_exists systemctl || fail "XrayR 自用冻结版安装器仅支持使用 systemd 的系统。"

requested_version=${1:-$FROZEN_VERSION}
[[ $requested_version == v* ]] || requested_version="v${requested_version}"
if [[ $requested_version != "$FROZEN_VERSION" ]]; then
    fail "自用仓库仅提供固定版本 ${FROZEN_VERSION}。"
fi

case $(uname -m) in
    x86_64 | amd64) release_arch="64" ;;
    aarch64 | arm64) release_arch="arm64-v8a" ;;
    s390x) release_arch="s390x" ;;
    *) fail "不支持的 CPU 架构：$(uname -m)" ;;
esac

if ! command_exists unzip || ! command_exists sha256sum ||
   { ! command_exists curl && ! command_exists wget; }; then
    warn "正在安装 XrayR 所需依赖..."
    install_dependencies || fail "依赖安装失败。"
fi

temp_dir=$(mktemp -d /tmp/xrayr-official.XXXXXX) || fail "无法创建临时目录。"
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

archive_name="XrayR-linux-${release_arch}.zip"
archive_url="${SELF_HOSTED_RELEASE_URL}/${archive_name}"
archive_file="${temp_dir}/${archive_name}"
checksum_file="${temp_dir}/SHA256SUMS"
extract_dir="${temp_dir}/extract"

info "正在从 Taylor000/XrayR 下载自用冻结版 ${FROZEN_VERSION} (${release_arch})..."
download_file "$archive_url" "$archive_file" || fail "自用仓库安装包下载失败：${archive_url}"
download_file "${SELF_HOSTED_RELEASE_URL}/SHA256SUMS" "$checksum_file" || fail "自用仓库校验文件下载失败。"

expected_sha256=$(awk -v name="$archive_name" '$2 == name { print $1; exit }' "$checksum_file")
actual_sha256=$(sha256sum "$archive_file" | awk '{print $1}')
[[ -n "$expected_sha256" ]] || fail "自用仓库校验文件中缺少 ${archive_name} 的 SHA-256。"
[[ ${actual_sha256,,} == ${expected_sha256,,} ]] || fail "发布包 SHA-256 校验失败，已取消安装。"

mkdir -p "$extract_dir"
unzip -q "$archive_file" -d "$extract_dir" || fail "官方发布包解压失败。"
[[ -x "$extract_dir/XrayR" || -f "$extract_dir/XrayR" ]] || fail "发布包中缺少 XrayR 主程序。"
[[ -f "$extract_dir/config.yml" ]] || fail "发布包中缺少默认配置文件。"

download_file "${VENDOR_RAW_URL}/xrayr/XrayR-official.service" \
    "$temp_dir/XrayR.service" || fail "服务文件下载失败。"
download_file "${VENDOR_RAW_URL}/xrayr/XrayR.sh" \
    "$temp_dir/XrayR.sh" || fail "管理脚本下载失败。"
grep -q '^ExecStart=.* --config /etc/XrayR/config.yml$' "$temp_dir/XrayR.service" ||
    fail "服务文件格式无效。"
bash -n "$temp_dir/XrayR.sh" || fail "管理脚本未通过 Bash 语法检查。"

had_config=0
[[ -f "$CONFIG_DIR/config.yml" ]] && had_config=1

install -d -m 755 "$INSTALL_DIR" "$CONFIG_DIR"
backup_file "$INSTALL_DIR/XrayR" || fail "无法备份现有 XrayR 主程序。"
backup_file "$SERVICE_FILE" || fail "无法备份现有 XrayR 服务文件。"
backup_file "$MANAGER_FILE" || fail "无法备份现有 XrayR 管理脚本。"

systemctl stop XrayR 2>/dev/null || true
install -m 755 "$extract_dir/XrayR" "$INSTALL_DIR/XrayR"
install -m 644 "$temp_dir/XrayR.service" "$SERVICE_FILE"
install -m 755 "$temp_dir/XrayR.sh" "$MANAGER_FILE"

for data_file in geoip.dat geosite.dat; do
    [[ -f "$extract_dir/$data_file" ]] &&
        install -m 644 "$extract_dir/$data_file" "$CONFIG_DIR/$data_file"
done

if (( had_config == 0 )); then
    install -m 600 "$extract_dir/config.yml" "$CONFIG_DIR/config.yml"
fi

for optional_file in dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
    if [[ -f "$extract_dir/$optional_file" && ! -e "$CONFIG_DIR/$optional_file" ]]; then
        install -m 644 "$extract_dir/$optional_file" "$CONFIG_DIR/$optional_file"
    fi
done

if [[ -e /usr/bin/xrayr && ! -L /usr/bin/xrayr ]]; then
    backup_file /usr/bin/xrayr || fail "无法备份现有 xrayr 命令。"
    rm -f /usr/bin/xrayr
fi
ln -sfn "$MANAGER_FILE" /usr/bin/xrayr
printf '%s\n' "frozen" > "$CONFIG_DIR/install-source"

systemctl daemon-reload
systemctl enable XrayR >/dev/null || fail "XrayR 开机自启设置失败。"

if (( had_config == 1 )); then
    if systemctl restart XrayR && systemctl is-active --quiet XrayR; then
        info "XrayR 服务已使用原配置重新启动。"
    else
        warn "XrayR 已安装，但原配置未能正常启动，请执行 xrayr status 检查。"
    fi
else
    warn "已生成默认配置，填写面板参数前不会启动 XrayR 服务。"
fi

info "XrayR 自用冻结版 ${FROZEN_VERSION} 安装完成。管理命令：xrayr"
warn "该版本固定不更新，不会再获得功能或安全更新。"
