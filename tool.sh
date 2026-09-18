#!/usr/bin/env bash

set -o pipefail

# 自动修复 Windows 换行符问题
CURRENT_SCRIPT=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
if [[ -f "$CURRENT_SCRIPT" && -w "$CURRENT_SCRIPT" && ! -L "$0" ]]; then
    sed -i 's/\r$//' "$CURRENT_SCRIPT" 2>/dev/null
fi

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 作者与脚本信息
AUTHOR_GITHUB="https://github.com/Taylor000"
SCRIPT_NAME="一个人的脚本百宝箱"
SHORTCUT_CMD="tool"
SCRIPT_VERSION="2.2.9"
MIN_SUPPORTED_VERSION="2.2.9"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/Taylor000/tool/master/tool.sh"
REPOSITORY_RAW_URL="https://raw.githubusercontent.com/Taylor000/tool"
VENDOR_RAW_URL="https://raw.githubusercontent.com/Taylor000/tool/master/vendor"
USAGE_COUNTER_URL="https://hits.sh/github.com/Taylor000/tool.svg?label=uses&color=blue"
REPOSITORY_COMMIT_API_URL="https://api.github.com/repos/Taylor000/tool/commits/master"
KOMARI_INSTALL_URL="https://raw.githubusercontent.com/Taylor000/komari/main/install-komari.sh"
KOMARI_AGENT_INSTALL_URL="https://raw.githubusercontent.com/Taylor000/komari-agent/main/install.sh"
XRAYR_INSTALL_URL="https://raw.githubusercontent.com/Taylor000/XrayR/master/install.sh"
V2NODE_INSTALL_URL="https://raw.githubusercontent.com/Taylor000/v2node/main/script/install.sh"

# 默认全局配置
DEFAULT_PORT="11156"
DEFAULT_PASS="github.taylor000"
BIND_IP="127.0.0.1"
PUBLIC_BIND_IP="0.0.0.0"
APT_INDEX_REFRESHED=0
DEBIAN_11_SNAPSHOT="20260831T211304Z"
ACTIVE_REPOSITORY_REVISION=""
WIN10_LTSC_IMAGE_URL="https://dl.lamp.sh/vhd/zh-cn_windows10_ltsc.xz"
WIN11_LTSC_IMAGE_URL="https://dl.lamp.sh/vhd/zh-cn_win11_ltsc.xz"
TOOL_STATE_DIR="/etc/taylor-tool"
UPDATE_REVISION_FILE="${TOOL_STATE_DIR}/repository-revision"
PREFERRED_IPV4_CONFIG_DIR="$TOOL_STATE_DIR"
PREFERRED_IPV4_CONFIG_FILE="${PREFERRED_IPV4_CONFIG_DIR}/preferred-ipv4.conf"
PREFERRED_IPV4_SERVICE="taylor-tool-preferred-ipv4.service"
PREFERRED_IPV4_UNIT_FILE="/etc/systemd/system/${PREFERRED_IPV4_SERVICE}"

# 检查是否为 Root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行此脚本！${NC}" && exit 1

# 空输入计数器
empty_count=0

info() {
    echo -e "${GREEN}$*${NC}"
}

warn() {
    echo -e "${YELLOW}$*${NC}"
}

error() {
    echo -e "${RED}$*${NC}" >&2
}

pause_menu() {
    read -r -p "按回车继续..."
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

fetch_url() {
    local url=$1

    if command_exists curl; then
        curl --fail --location --silent --show-error \
            --connect-timeout 10 --max-time 20 --retry 1 \
            -A "Taylor000-tool/${SCRIPT_VERSION}" "$url"
    elif command_exists wget; then
        wget --https-only --quiet --timeout=20 --tries=2 \
            --user-agent="Taylor000-tool/${SCRIPT_VERSION}" -O- "$url"
    else
        return 1
    fi
}

record_usage_count() {
    local counter_svg

    if [[ ${TOOL_USAGE_RECORDED:-0} == "1" ]]; then
        USAGE_COUNT=${TOOL_USAGE_COUNT:-"暂不可用"}
        return 0
    fi

    counter_svg=$(fetch_url "$USAGE_COUNTER_URL" 2>/dev/null) || {
        USAGE_COUNT="暂不可用"
        export TOOL_USAGE_RECORDED=1
        export TOOL_USAGE_COUNT="$USAGE_COUNT"
        return 0
    }
    USAGE_COUNT=$(printf '%s' "$counter_svg" |
        sed -nE 's/.*aria-label="uses: ([0-9]+)".*/\1/p' |
        head -n 1)
    USAGE_COUNT=${USAGE_COUNT:-"暂不可用"}
    export TOOL_USAGE_RECORDED=1
    export TOOL_USAGE_COUNT="$USAGE_COUNT"
}

fetch_repository_revision() {
    local response line

    response=$(fetch_url "${REPOSITORY_COMMIT_API_URL}?t=$(date +%s)" 2>/dev/null) || return 1
    while IFS= read -r line; do
        if [[ $line =~ \"sha\"[[:space:]]*:[[:space:]]*\"([0-9a-f]{40})\" ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done <<< "$response"
    return 1
}

read_saved_repository_revision() {
    local revision=""

    [[ -f $UPDATE_REVISION_FILE ]] || return 1
    IFS= read -r revision < "$UPDATE_REVISION_FILE" || true
    [[ $revision =~ ^[0-9a-f]{40}$ ]] || return 1
    printf '%s\n' "$revision"
}

save_repository_revision() {
    local revision=$1 revision_temp

    [[ $revision =~ ^[0-9a-f]{40}$ ]] || return 1
    revision_temp=$(mktemp /tmp/tool-revision.XXXXXX) || return 1
    printf '%s\n' "$revision" > "$revision_temp"
    if ! install -d -m 755 "$TOOL_STATE_DIR" ||
       ! install -m 600 "$revision_temp" "$UPDATE_REVISION_FILE"; then
        rm -f "$revision_temp"
        return 1
    fi
    rm -f "$revision_temp"
}

check_script_update() {
    local remote_script remote_script_url remote_version remote_min_version
    local remote_revision="" saved_revision="" update_reason=""
    local version_update=0 revision_update=0

    remote_revision=$(fetch_repository_revision 2>/dev/null || true)
    if [[ $remote_revision =~ ^[0-9a-f]{40}$ ]]; then
        ACTIVE_REPOSITORY_REVISION="$remote_revision"
    fi
    if [[ $remote_revision =~ ^[0-9a-f]{40}$ ]]; then
        remote_script_url="${REPOSITORY_RAW_URL}/${remote_revision}/tool.sh"
    else
        remote_script_url="${SCRIPT_RAW_URL}?t=$(date +%s)"
    fi

    remote_script=$(mktemp /tmp/tool-update.XXXXXX) || return 0
    if ! download_script "$remote_script_url" "$remote_script"; then
        rm -f "$remote_script"
        warn "暂时无法检查脚本更新，将继续运行当前版本。"
        return 0
    fi

    remote_version=$(sed -nE 's/^SCRIPT_VERSION="([^"]+)".*/\1/p' "$remote_script" | head -n 1)
    remote_min_version=$(sed -nE 's/^MIN_SUPPORTED_VERSION="([^"]+)".*/\1/p' "$remote_script" | head -n 1)
    if [[ -z "$remote_version" ]]; then
        rm -f "$remote_script"
        warn "远端脚本缺少版本号，已跳过自动更新。"
        return 0
    fi

    if [[ $(printf '%s\n%s\n' "$SCRIPT_VERSION" "$remote_version" | sort -V | tail -n 1) == "$remote_version" &&
          "$SCRIPT_VERSION" != "$remote_version" ]]; then
        version_update=1
    fi

    saved_revision=$(read_saved_repository_revision 2>/dev/null || true)
    if [[ $remote_revision =~ ^[0-9a-f]{40}$ &&
          $saved_revision =~ ^[0-9a-f]{40}$ &&
          $remote_revision != "$saved_revision" ]]; then
        revision_update=1
    fi

    if (( version_update == 0 && revision_update == 0 )); then
        rm -f "$remote_script"
        if [[ $remote_revision =~ ^[0-9a-f]{40}$ &&
              ! $saved_revision =~ ^[0-9a-f]{40}$ ]]; then
            save_repository_revision "$remote_revision" ||
                warn "无法保存脚本修订号；下次仍会重新检查更新。"
        fi
        return 0
    fi

    if (( version_update == 1 )); then
        update_reason="版本 ${SCRIPT_VERSION} → ${remote_version}"
    else
        update_reason="仓库脚本已更新 (${saved_revision:0:7} → ${remote_revision:0:7})"
    fi
    if [[ -n "$remote_min_version" &&
          $(printf '%s\n%s\n' "$SCRIPT_VERSION" "$remote_min_version" | sort -V | head -n 1) == "$SCRIPT_VERSION" &&
          "$SCRIPT_VERSION" != "$remote_min_version" ]]; then
        warn "当前版本低于最低支持版本 v${remote_min_version}。"
    fi
    warn "检测到${update_reason}，正在强制更新主脚本..."

    if ! install -m 755 "$remote_script" "$CURRENT_SCRIPT"; then
        error "脚本更新失败，当前版本未被替换。"
        rm -f "$remote_script"
        return 0
    fi
    rm -f "$remote_script"
    if [[ $remote_revision =~ ^[0-9a-f]{40}$ ]] &&
       ! save_repository_revision "$remote_revision"; then
        warn "主脚本已更新，但无法保存仓库修订号；请重新运行 tool。"
        return 0
    fi
    info "脚本已更新到 ${remote_version}，正在重新启动..."
    exec "$CURRENT_SCRIPT"
}

is_debian_11() {
    local distro_id="" distro_version=""

    if [[ -r /etc/os-release ]]; then
        distro_id=$(sed -nE 's/^ID="?([^" ]+)"?$/\1/p' /etc/os-release | head -n 1)
        distro_version=$(sed -nE 's/^VERSION_ID="?([^" ]+)"?$/\1/p' /etc/os-release | head -n 1)
    fi
    [[ $distro_id == "debian" && $distro_version == "11" ]]
}

install_debian_11_packages() {
    local temp_dir sources_file status=1
    local -a apt_options packages=("$@")

    temp_dir=$(mktemp -d /tmp/tool-bullseye-apt.XXXXXX) || return 1
    sources_file="${temp_dir}/sources.list"
    mkdir -p "${temp_dir}/lists/partial" "${temp_dir}/archives/partial"
    cat > "$sources_file" <<EOF
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_11_SNAPSHOT}/ bullseye main
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_11_SNAPSHOT}/ bullseye-updates main
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${DEBIAN_11_SNAPSHOT}/ bullseye-security main
EOF

    apt_options=(
        -o "Dir::Etc::sourcelist=${sources_file}"
        -o Dir::Etc::sourceparts=-
        -o "Dir::State::lists=${temp_dir}/lists"
        -o "Dir::Cache::archives=${temp_dir}/archives"
        -o Acquire::Check-Valid-Until=false
        -o Acquire::ForceIPv4=true
        -o Acquire::Retries=3
        -o Acquire::http::No-Cache=true
        -o Acquire::https::No-Cache=true
    )

    warn "Debian 11 使用固定软件仓库快照安装：${packages[*]}"
    if apt-get "${apt_options[@]}" update &&
       DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install -y "${packages[@]}"; then
        status=0
        APT_INDEX_REFRESHED=1
    else
        error "Debian 11 固定软件仓库安装失败。"
    fi

    rm -rf "$temp_dir"
    return "$status"
}

install_packages() {
    (( $# > 0 )) || return 0

    if command_exists apt-get; then
        if is_debian_11; then
            install_debian_11_packages "$@"
            return $?
        fi
        if (( APT_INDEX_REFRESHED == 0 )); then
            warn "正在刷新 APT 软件包索引..."
            if DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 update; then
                APT_INDEX_REFRESHED=1
            else
                warn "APT 软件包索引刷新未完全成功，将尝试使用现有索引继续安装。"
            fi
        fi
        DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y "$@"
    elif command_exists dnf; then
        dnf install -y "$@"
    elif command_exists yum; then
        yum install -y "$@"
    elif command_exists apk; then
        apk add --no-cache "$@"
    else
        error "无法识别包管理器，请手动安装：$*"
        return 1
    fi
}

download_file() {
    local url=$1
    local destination=$2
    local status

    rm -f "$destination"
    if command_exists curl; then
        curl --fail --location --silent --show-error \
            --connect-timeout 15 --max-time 60 --retry 2 \
            "$url" -o "$destination"
        status=$?
    elif command_exists wget; then
        wget --https-only --timeout=30 --tries=3 -O "$destination" "$url"
        status=$?
    else
        error "系统缺少 curl 或 wget，无法下载文件。"
        return 1
    fi

    if (( status != 0 )); then
        error "下载失败：$url"
        rm -f "$destination"
        return 1
    fi
    if [[ ! -s "$destination" ]]; then
        error "下载文件为空：$url"
        rm -f "$destination"
        return 1
    fi
}

download_script() {
    local url=$1
    local destination=$2

    download_file "$url" "$destination" || return 1
    if head -c 512 "$destination" | grep -Eiq '<!doctype html|<html|under maintenance|404 not found'; then
        error "下载结果不是有效脚本，可能是错误页面：$url"
        rm -f "$destination"
        return 1
    fi
    if ! bash -n "$destination"; then
        error "下载的脚本未通过 Bash 语法检查：$url"
        rm -f "$destination"
        return 1
    fi
    chmod 700 "$destination"
}

resolve_remote_script_url() {
    local url=$1 suffix separator="?"

    if [[ $url == "$VENDOR_RAW_URL/"* &&
          $ACTIVE_REPOSITORY_REVISION =~ ^[0-9a-f]{40}$ ]]; then
        suffix=${url#"$VENDOR_RAW_URL/"}
        printf '%s/%s/vendor/%s\n' \
            "$REPOSITORY_RAW_URL" "$ACTIVE_REPOSITORY_REVISION" "$suffix"
        return 0
    fi

    [[ $url == *\?* ]] && separator="&"
    printf '%s%stool_cache_bust=%s-%s-%s\n' \
        "$url" "$separator" "$(date +%s)" "$$" "$RANDOM"
}

run_remote_script() {
    local url=$1
    shift
    local script_file
    url=$(resolve_remote_script_url "$url") || return 1
    script_file=$(mktemp /tmp/tool-script.XXXXXX) || return 1

    if ! download_script "$url" "$script_file"; then
        rm -f "$script_file"
        return 1
    fi

    bash "$script_file" "$@"
    local status=$?
    rm -f "$script_file"
    return "$status"
}

run_remote_script_with_input() {
    local input=$1
    local url=$2
    shift 2
    local script_file
    url=$(resolve_remote_script_url "$url") || return 1
    script_file=$(mktemp /tmp/tool-script.XXXXXX) || return 1

    if ! download_script "$url" "$script_file"; then
        rm -f "$script_file"
        return 1
    fi

    printf '%s\n' "$input" | bash "$script_file" "$@"
    local status=${PIPESTATUS[1]}
    rm -f "$script_file"
    return "$status"
}

valid_port() {
    [[ $1 =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_container_name() {
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]
}

choose_service_bind_ip() {
    local description=$1
    local answer

    echo -e "${YELLOW}${description}${NC}"
    read -r -p "是否允许其他服务器通过公网连接？(y/n, 默认n): " answer
    if [[ $answer == [yY] ]]; then
        SERVICE_BIND_IP="$PUBLIC_BIND_IP"
        warn "该服务端口将监听所有网卡，请同时配置云防火墙仅允许可信来源 IP。"
    else
        SERVICE_BIND_IP="$BIND_IP"
        info "该服务端口仅监听本机，不会直接暴露到公网。"
    fi
}

container_is_running() {
    [[ $(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null) == "true" ]]
}

wait_for_container() {
    local name=$1
    local retries=${2:-10}
    local i

    for ((i = 0; i < retries; i++)); do
        container_is_running "$name" && return 0
        sleep 1
    done
    return 1
}

# 基础依赖检测与安装
check_base_dependencies() {
    local missing=()
    if ! command_exists curl && ! command_exists wget; then
        missing+=(curl)
    fi

    if command_exists apt-get; then
        command_exists update-ca-certificates || missing+=(ca-certificates)
    fi

    if (( ${#missing[@]} > 0 )); then
        warn "正在安装基础依赖：${missing[*]}"
        install_packages "${missing[@]}" || {
            error "基础依赖安装失败，脚本无法继续。"
            exit 1
        }
    fi

    if ! command_exists ip; then
        if command_exists apt-get; then
            install_packages iproute2
        elif command_exists dnf || command_exists yum; then
            install_packages iproute
        elif command_exists apk; then
            install_packages iproute2
        else
            error "无法识别包管理器，请手动安装 ip 命令。"
            exit 1
        fi || {
            error "ip 命令安装失败，脚本无法继续。"
            exit 1
        }
    fi
}

check_dd_dependencies() {
    warn "正在检查 DD/重装系统所需依赖..."

    if command_exists apt-get; then
        install_packages wget openssl xz-utils gzip cpio file util-linux ca-certificates iproute2 || return 1
    elif command_exists dnf; then
        install_packages wget openssl xz gzip cpio file util-linux ca-certificates iproute || return 1
    elif command_exists yum; then
        install_packages wget openssl xz gzip cpio file util-linux ca-certificates iproute || return 1
    elif command_exists apk; then
        install_packages wget openssl xz gzip cpio file util-linux ca-certificates iproute2 || return 1
    else
        error "无法识别包管理器，请手动安装 wget openssl xz gzip cpio file lsblk ip 后再运行 DD 功能。"
        return 1
    fi
}

check_windows_x86_requirements() {
    local architecture

    architecture=$(uname -m)
    if [[ $architecture != "x86_64" && $architecture != "amd64" ]]; then
        error "Windows 11 LTSC 镜像仅支持 x86_64 架构，当前架构：$architecture"
        return 1
    fi
}

# 获取系统基本网络信息
get_network_info() {
    LOCAL_IP=$(curl --fail --silent --show-error --ipv4 --max-time 10 https://api64.ipify.org \
        || curl --fail --silent --show-error --ipv4 --max-time 10 https://ifconfig.me \
        || curl --fail --silent --show-error --ipv4 --max-time 10 https://ip.gs \
        || true)
    LOCAL_GATEWAY=$(ip route show default | awk 'NR==1 {print $3}')
    LOCAL_MASK="255.255.255.0"

    if [[ -z "$LOCAL_IP" ]]; then
        error "无法获取公网 IPv4 地址。"
        return 1
    fi
}

valid_ipv4() {
    local address=$1 octet value
    local -a octets

    [[ $address =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$address"
    (( ${#octets[@]} == 4 )) || return 1
    for octet in "${octets[@]}"; do
        value=$((10#$octet))
        (( value >= 0 && value <= 255 )) || return 1
    done
}

is_public_ipv4() {
    local address=$1
    local first second third fourth

    valid_ipv4 "$address" || return 1
    IFS='.' read -r first second third fourth <<< "$address"
    first=$((10#$first))
    second=$((10#$second))
    third=$((10#$third))
    fourth=$((10#$fourth))

    (( first == 0 || first == 10 || first == 127 || first >= 224 )) && return 1
    (( first == 100 && second >= 64 && second <= 127 )) && return 1
    (( first == 169 && second == 254 )) && return 1
    (( first == 172 && second >= 16 && second <= 31 )) && return 1
    (( first == 192 && second == 0 )) && return 1
    (( first == 192 && second == 168 )) && return 1
    (( first == 198 && (second == 18 || second == 19) )) && return 1
    (( first == 198 && second == 51 && third == 100 )) && return 1
    (( first == 203 && second == 0 && third == 113 )) && return 1
    return 0
}

valid_interface_name() {
    [[ $1 =~ ^[a-zA-Z0-9_.:-]+$ ]]
}

route_field() {
    local route_line=$1 wanted=$2 index
    local -a route_parts

    read -r -a route_parts <<< "$route_line"
    for ((index = 0; index + 1 < ${#route_parts[@]}; index++)); do
        if [[ ${route_parts[index]} == "$wanted" ]]; then
            printf '%s\n' "${route_parts[index + 1]}"
            return 0
        fi
    done
    return 1
}

get_active_ipv4_route() {
    local route_line

    route_line=$(ip -4 route get 1.1.1.1 2>/dev/null | head -n 1) || return 1
    [[ -n $route_line ]] || return 1
    ACTIVE_IPV4_INTERFACE=$(route_field "$route_line" dev) || return 1
    ACTIVE_IPV4_INTERFACE=${ACTIVE_IPV4_INTERFACE%%@*}
    ACTIVE_IPV4_SOURCE=$(route_field "$route_line" src) || return 1
    ACTIVE_IPV4_GATEWAY=$(route_field "$route_line" via 2>/dev/null || true)
    valid_interface_name "$ACTIVE_IPV4_INTERFACE" && valid_ipv4 "$ACTIVE_IPV4_SOURCE"
}

address_is_bound() {
    local interface=$1 address=$2
    local _index listed_interface family cidr remainder listed_address

    while read -r _index listed_interface family cidr remainder; do
        listed_interface=${listed_interface%%@*}
        listed_address=${cidr%%/*}
        if [[ $family == "inet" && $listed_interface == "$interface" && $listed_address == "$address" ]]; then
            return 0
        fi
    done < <(ip -o -4 addr show dev "$interface" up 2>/dev/null)
    return 1
}

collect_public_ipv4_addresses() {
    local _index interface family cidr remainder address existing duplicate

    PUBLIC_IPV4_ADDRESSES=()
    PUBLIC_IPV4_PREFIXES=()
    PUBLIC_IPV4_INTERFACES=()
    while read -r _index interface family cidr remainder; do
        [[ $family == "inet" ]] || continue
        interface=${interface%%@*}
        address=${cidr%%/*}
        is_public_ipv4 "$address" || continue
        duplicate=0
        for existing in "${PUBLIC_IPV4_ADDRESSES[@]}"; do
            [[ $existing == "$address" ]] && duplicate=1
        done
        (( duplicate == 1 )) && continue
        PUBLIC_IPV4_ADDRESSES+=("$address")
        PUBLIC_IPV4_PREFIXES+=("$cidr")
        PUBLIC_IPV4_INTERFACES+=("$interface")
    done < <(ip -o -4 addr show up scope global 2>/dev/null)
}

probe_outbound_ipv4() {
    local bind_address=${1:-} response url
    local -a curl_arguments

    command_exists curl || return 1
    curl_arguments=(--fail --location --silent --ipv4 --noproxy '*'
        --connect-timeout 4 --max-time 8)
    [[ -n $bind_address ]] && curl_arguments+=(--interface "$bind_address")

    for url in https://api64.ipify.org https://ifconfig.me/ip https://ip.gs; do
        response=$(curl "${curl_arguments[@]}" "$url" 2>/dev/null | tr -d '[:space:]') || continue
        if valid_ipv4 "$response"; then
            printf '%s\n' "$response"
            return 0
        fi
    done
    return 1
}

get_default_route_for_interface() {
    local interface=$1 route_line route_gateway

    while IFS= read -r route_line; do
        [[ -n $route_line && $route_line != *" nexthop "* ]] || continue
        route_gateway=$(route_field "$route_line" via 2>/dev/null || true)
        if [[ -z ${ACTIVE_IPV4_GATEWAY:-} || $route_gateway == "$ACTIVE_IPV4_GATEWAY" ]]; then
            printf '%s\n' "$route_line"
            return 0
        fi
    done < <(ip -4 route show table main default dev "$interface" 2>/dev/null)
    return 1
}

set_preferred_ipv4_source() {
    local interface=$1 address=$2 route_line gateway metric
    local -a route_command

    valid_interface_name "$interface" && valid_ipv4 "$address" || return 1
    address_is_bound "$interface" "$address" || return 1
    route_line=$(get_default_route_for_interface "$interface") || return 1
    [[ $route_line != *" nexthop "* ]] || return 1

    gateway=$(route_field "$route_line" via 2>/dev/null || true)
    metric=$(route_field "$route_line" metric 2>/dev/null || true)
    [[ -z $gateway ]] || valid_ipv4 "$gateway" || return 1
    [[ -z $metric || $metric =~ ^[0-9]+$ ]] || return 1

    route_command=(ip -4 route replace default)
    [[ -n $gateway ]] && route_command+=(via "$gateway")
    route_command+=(dev "$interface" src "$address")
    [[ $route_line == *" onlink"* ]] && route_command+=(onlink)
    [[ -n $metric ]] && route_command+=(metric "$metric")
    "${route_command[@]}"
}

show_public_ipv4_status() {
    local external_ip="检测失败" marker selectable index saved_address="" saved_interface=""

    collect_public_ipv4_addresses
    if ! get_active_ipv4_route; then
        error "无法读取当前 IPv4 默认出口路由。"
        return 1
    fi
    external_ip=$(probe_outbound_ipv4 || true)
    external_ip=${external_ip:-"检测失败"}

    if [[ -f $PREFERRED_IPV4_CONFIG_FILE ]]; then
        saved_interface=$(sed -n 's/^interface=//p' "$PREFERRED_IPV4_CONFIG_FILE" | head -n 1)
        saved_address=$(sed -n 's/^address=//p' "$PREFERRED_IPV4_CONFIG_FILE" | head -n 1)
    fi

    echo -e "\n${BLUE}================ IPv4 默认出口管理 ================${NC}"
    if (( ${#PUBLIC_IPV4_ADDRESSES[@]} == 0 )); then
        warn "没有检测到直接绑定在网卡上的公网 IPv4 地址。"
    else
        printf '%-5s %-14s %-20s %-12s %-12s\n' "序号" "网卡" "公网 IPv4" "当前首选" "可切换"
        for ((index = 0; index < ${#PUBLIC_IPV4_ADDRESSES[@]}; index++)); do
            marker="否"
            selectable="否"
            if [[ ${PUBLIC_IPV4_INTERFACES[index]} == "$ACTIVE_IPV4_INTERFACE" ]]; then
                selectable="是"
                [[ ${PUBLIC_IPV4_ADDRESSES[index]} == "$ACTIVE_IPV4_SOURCE" ]] && marker="是"
            fi
            printf '%-5s %-14s %-20s %-12s %-12s\n' \
                "$((index + 1))" "${PUBLIC_IPV4_INTERFACES[index]}" \
                "${PUBLIC_IPV4_PREFIXES[index]}" "$marker" "$selectable"
        done
    fi
    echo -e "${BLUE}----------------------------------------------------${NC}"
    echo -e "默认出口网卡: ${YELLOW}${ACTIVE_IPV4_INTERFACE}${NC}"
    echo -e "内核首选源 IP: ${YELLOW}${ACTIVE_IPV4_SOURCE}${NC}"
    echo -e "外部检测出口 IP: ${YELLOW}${external_ip}${NC}"
    if [[ -n $ACTIVE_IPV4_GATEWAY ]]; then
        echo -e "默认网关: ${YELLOW}${ACTIVE_IPV4_GATEWAY}${NC}"
    fi
    if [[ -n $saved_address && -n $saved_interface ]]; then
        echo -e "永久设置: ${GREEN}${saved_interface} / ${saved_address}${NC}"
    else
        echo -e "永久设置: ${YELLOW}未启用${NC}"
    fi
    if valid_ipv4 "$external_ip" && [[ $external_ip != "$ACTIVE_IPV4_SOURCE" ]]; then
        warn "外部出口与内核源 IP 不同，可能存在云厂商 NAT/SNAT。"
    fi
    echo -e "${BLUE}====================================================${NC}"
}

write_preferred_ipv4_persistence() {
    local interface=$1 address=$2 config_temp unit_temp escaped_script

    if ! command_exists systemctl || [[ ! -d /run/systemd/system ]]; then
        error "当前系统未运行 systemd，只能使用临时切换模式。"
        return 1
    fi
    [[ $CURRENT_SCRIPT == /* && -f $CURRENT_SCRIPT ]] || {
        error "无法确定当前脚本的绝对路径，不能创建永久设置。"
        return 1
    }

    config_temp=$(mktemp /tmp/tool-preferred-ipv4-config.XXXXXX) || return 1
    unit_temp=$(mktemp /tmp/tool-preferred-ipv4-unit.XXXXXX) || {
        rm -f "$config_temp"
        return 1
    }
    printf 'interface=%s\naddress=%s\n' "$interface" "$address" > "$config_temp"

    escaped_script=${CURRENT_SCRIPT//%/%%}
    escaped_script=${escaped_script//\\/\\\\}
    escaped_script=${escaped_script//\"/\\\"}
    cat > "$unit_temp" <<EOF
[Unit]
Description=Apply Taylor Tool preferred IPv4 source address
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash "$escaped_script" --apply-preferred-ipv4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    if ! install -d -m 755 "$PREFERRED_IPV4_CONFIG_DIR" ||
       ! install -m 600 "$config_temp" "$PREFERRED_IPV4_CONFIG_FILE" ||
       ! install -m 644 "$unit_temp" "$PREFERRED_IPV4_UNIT_FILE" ||
       ! systemctl daemon-reload ||
       ! systemctl enable "$PREFERRED_IPV4_SERVICE" >/dev/null; then
        error "永久配置写入失败。"
        rm -f "$config_temp" "$unit_temp"
        rm -f "$PREFERRED_IPV4_CONFIG_FILE" "$PREFERRED_IPV4_UNIT_FILE"
        rmdir "$PREFERRED_IPV4_CONFIG_DIR" 2>/dev/null || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        return 1
    fi
    rm -f "$config_temp" "$unit_temp"
    info "已设置开机首选 IPv4：${interface} / ${address}"
}

remove_preferred_ipv4_persistence() {
    local quiet=${1:-0}

    if [[ ! -f $PREFERRED_IPV4_CONFIG_FILE && ! -f $PREFERRED_IPV4_UNIT_FILE ]]; then
        (( quiet == 1 )) || warn "当前没有永久 IPv4 出口设置。"
        return 0
    fi
    if command_exists systemctl; then
        systemctl disable --now "$PREFERRED_IPV4_SERVICE" >/dev/null 2>&1 || true
    fi
    rm -f "$PREFERRED_IPV4_CONFIG_FILE" "$PREFERRED_IPV4_UNIT_FILE"
    rmdir "$PREFERRED_IPV4_CONFIG_DIR" 2>/dev/null || true
    command_exists systemctl && systemctl daemon-reload >/dev/null 2>&1 || true
    (( quiet == 1 )) || info "已取消开机永久 IPv4 出口设置；当前运行中的路由未改变。"
}

apply_saved_preferred_ipv4() {
    local interface address attempt

    [[ -f $PREFERRED_IPV4_CONFIG_FILE ]] || {
        error "未找到永久 IPv4 配置。"
        return 1
    }
    interface=$(sed -n 's/^interface=//p' "$PREFERRED_IPV4_CONFIG_FILE" | head -n 1)
    address=$(sed -n 's/^address=//p' "$PREFERRED_IPV4_CONFIG_FILE" | head -n 1)
    valid_interface_name "$interface" && is_public_ipv4 "$address" || {
        error "永久 IPv4 配置内容无效。"
        return 1
    }

    for ((attempt = 1; attempt <= 15; attempt++)); do
        if address_is_bound "$interface" "$address" &&
           get_active_ipv4_route &&
           [[ $ACTIVE_IPV4_INTERFACE == "$interface" ]] &&
           set_preferred_ipv4_source "$interface" "$address"; then
            get_active_ipv4_route
            if [[ $ACTIVE_IPV4_INTERFACE == "$interface" && $ACTIVE_IPV4_SOURCE == "$address" ]]; then
                info "已应用永久首选 IPv4：${interface} / ${address}"
                return 0
            fi
        fi
        sleep 2
    done
    error "网络就绪后仍无法应用永久首选 IPv4。"
    return 1
}

switch_preferred_ipv4() {
    local mode=$1 selection selected_index selected_address selected_interface
    local old_source preflight_ip actual_ip confirm

    collect_public_ipv4_addresses
    get_active_ipv4_route || {
        error "无法读取当前 IPv4 默认出口。"
        return 1
    }
    (( ${#PUBLIC_IPV4_ADDRESSES[@]} > 0 )) || {
        error "没有可选择的公网 IPv4。"
        return 1
    }

    read -r -p "请输入要设为默认出口的 IP 序号: " selection
    [[ $selection =~ ^[0-9]+$ ]] || {
        error "请输入有效序号。"
        return 1
    }
    selected_index=$((10#$selection - 1))
    (( selected_index >= 0 && selected_index < ${#PUBLIC_IPV4_ADDRESSES[@]} )) || {
        error "选择超出范围。"
        return 1
    }
    selected_address=${PUBLIC_IPV4_ADDRESSES[selected_index]}
    selected_interface=${PUBLIC_IPV4_INTERFACES[selected_index]}
    if [[ $selected_interface != "$ACTIVE_IPV4_INTERFACE" ]]; then
        error "所选 IP 位于非默认网卡 ${selected_interface}。为避免 SSH 失联，本版本不自动切换网关或网卡 metric。"
        return 1
    fi

    warn "正在使用 ${selected_address} 进行切换前公网出口验证..."
    preflight_ip=$(probe_outbound_ipv4 "$selected_address" || true)
    if [[ $preflight_ip != "$selected_address" ]]; then
        if valid_ipv4 "$preflight_ip"; then
            error "该地址出站后被转换为 ${preflight_ip}，上游可能存在 SNAT，已取消切换。"
        else
            error "无法使用 ${selected_address} 访问公网，已取消切换。"
        fi
        return 1
    fi

    if [[ $mode == "permanent" ]]; then
        warn "将把 ${selected_address} 设置为当前及开机后的默认 IPv4 出口。"
    else
        warn "将临时把 ${selected_address} 设置为默认 IPv4 出口，重启或重载网络后可能失效。"
    fi
    read -r -p "确认修改请输入 YES: " confirm
    [[ $confirm == "YES" ]] || {
        warn "已取消修改。"
        return 0
    }

    old_source=$ACTIVE_IPV4_SOURCE
    if [[ $old_source != "$selected_address" ]]; then
        if ! set_preferred_ipv4_source "$selected_interface" "$selected_address"; then
            error "默认路由修改失败。"
            return 1
        fi
    fi

    get_active_ipv4_route || true
    actual_ip=$(probe_outbound_ipv4 || true)
    if [[ $ACTIVE_IPV4_INTERFACE != "$selected_interface" ||
          $ACTIVE_IPV4_SOURCE != "$selected_address" ||
          $actual_ip != "$selected_address" ]]; then
        error "切换后的路由或公网出口验证失败，正在恢复 ${old_source}。"
        set_preferred_ipv4_source "$selected_interface" "$old_source" ||
            error "自动恢复失败，请立即检查默认路由。"
        return 1
    fi

    info "默认 IPv4 出口已切换为 ${selected_address}（网卡 ${selected_interface}）。"
    if [[ $mode == "permanent" ]]; then
        if ! write_preferred_ipv4_persistence "$selected_interface" "$selected_address"; then
            warn "当前切换已经生效，但永久设置失败；重启后可能恢复。"
            return 1
        fi
    fi
}

public_ipv4_menu() {
    local network_choice remove_confirm

    if ! command_exists curl; then
        warn "此功能需要 curl 来验证实际公网出口，正在安装。"
        install_packages curl || {
            error "curl 安装失败，无法使用 IPv4 出口管理。"
            return 1
        }
    fi
    while true; do
        show_public_ipv4_status || true
        echo -e "${YELLOW} 1.${NC} 刷新检测"
        echo -e "${YELLOW} 2.${NC} 临时设置默认出口 IPv4"
        echo -e "${YELLOW} 3.${NC} 设置默认出口 IPv4 并永久生效"
        echo -e "${YELLOW} 4.${NC} 取消永久设置（不改变当前出口）"
        echo -e "${RED} 0.${NC} 返回主菜单"
        read -r -p "请选择操作: " network_choice
        case $network_choice in
            1) continue ;;
            2) switch_preferred_ipv4 temporary; pause_menu ;;
            3) switch_preferred_ipv4 permanent; pause_menu ;;
            4)
                read -r -p "确认取消开机永久设置？(y/n): " remove_confirm
                [[ $remove_confirm == [yY] ]] && remove_preferred_ipv4_persistence
                pause_menu
                ;;
            0) return 0 ;;
            *) error "选择无效。"; sleep 1 ;;
        esac
    done
}

# 开启 BBR 逻辑
enable_bbr() {
    local kernel_version bbr_script
    warn "正在检测并尝试开启 BBR..."
    kernel_version=$(uname -r | cut -d- -f1)
    if printf '%s\n%s\n' "4.9" "$kernel_version" | sort -V -C; then
        info "检测到内核版本 $kernel_version，支持直接开启 BBR。"
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        if sysctl -p && sysctl net.ipv4.tcp_congestion_control | grep -qw bbr; then
            info "BBR 开启成功！"
            return 0
        else
            error "直接开启 BBR 失败，准备运行内核安装脚本。"
        fi
    else
        warn "内核版本低于 4.9，准备运行内核安装脚本。"
    fi

    bbr_script=$(mktemp /tmp/tool-bbr.XXXXXX) || return 1
    download_script "${VENDOR_RAW_URL}/scripts/teddysun-bbr.sh" "$bbr_script" &&
        bash "$bbr_script"
    local status=$?
    rm -f "$bbr_script"
    return "$status"
}

# 检查并自动安装 Docker
check_docker() {
    if ! command_exists docker; then
        warn "检测到系统未安装 Docker，正在开始自动安装..."
        run_remote_script "${VENDOR_RAW_URL}/scripts/docker-get.sh" || {
            error "Docker 安装脚本执行失败。"
            return 1
        }
    fi

    if command_exists systemctl; then
        systemctl enable --now docker || {
            error "Docker 服务启动失败。"
            return 1
        }
    fi
    docker info >/dev/null 2>&1 || {
        error "Docker 已安装，但守护进程不可用。"
        return 1
    }
}

# 预检函数
check_installed() {
    if command_exists "$1" || [[ -f "/usr/bin/$1" ]] || [[ -f "/usr/local/bin/$1" ]] || [[ -d "/www/server/panel" && "$1" == "bt" ]]; then
        echo -e "${YELLOW}【预检提示】系统检测到已安装 ${BLUE}$2${NC}"
        echo -e "${YELLOW}快捷命令: ${RED}$3${NC}"
        read -r -p "是否仍然重新安装？(y/n, 默认n): " re_confirm
        if [[ $re_confirm != [yY] ]]; then
            return 1
        fi
    fi
    return 0
}

# 精简页眉显示
show_mini_header() {
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${GREEN}             ${SCRIPT_NAME}                  ${NC}"
    echo -e "${BLUE}     Author: ${YELLOW}${AUTHOR_GITHUB}${NC}"
    echo -e "${BLUE}     快捷启动命令: ${RED}${SHORTCUT_CMD}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    read -r -p "操作已结束。是否返回百宝箱主菜单？(y/n): " back_choice
    if [[ $back_choice != [yY] ]]; then
        echo -e "${GREEN}脚本已退出。${NC}"
        exit 0
    fi
}

# 菜单函数
show_menu() {
    clear 2>/dev/null || true
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}             ${SCRIPT_NAME}                  ${NC}"
    echo -e "${BLUE}     Author: ${YELLOW}${AUTHOR_GITHUB}${NC}"
    echo -e "${BLUE}     快捷启动命令: ${RED}${SHORTCUT_CMD}${NC}"
    echo -e "${BLUE}     当前版本: ${YELLOW}v${SCRIPT_VERSION}${NC}  累计调用: ${YELLOW}${USAGE_COUNT:-暂不可用}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW} 1.${NC} 显示系统基本信息与性能测试"
    echo -e "${YELLOW} 2.${NC} 修改系统 root 密码"
    echo -e "${YELLOW} 3.${NC} 修改 SSH 服务端口"
    echo -e "${YELLOW} 4.${NC} 安装 BBR 加速插件"
    echo -e "${YELLOW} 5.${NC} 安装 iperf3 网络测速工具"
    echo -e "${YELLOW} 6.${NC} 公网 IPv4 与默认出口管理"
    echo -e "${YELLOW} 7.${NC} 安装 Debian 11 系统 (萌咖版)"
    echo -e "${YELLOW} 8.${NC} 安装 Debian 12 系统 (萌咖版)"
    echo -e "${YELLOW} 9.${NC} 安装 Win10 LTSC 系统 (秋水逸冰)"
    echo -e "${YELLOW} 10.${NC} 安装旧版 Windows (veip007 交互版)"
    echo -e "${YELLOW} 11.${NC} 安装 Windows 11 LTSC 系统"
    echo -e "${YELLOW} 12.${NC} 安装 aaPanel 面板 (mzwrt 备份版)"
    echo -e "${YELLOW} 13.${NC} 安装 Docker 运行环境"
    echo -e "${YELLOW} 14.${NC} 安装 ServerStatus 监控探针"
    echo -e "${YELLOW} 15.${NC} 安装 Komari 1.2.0"
    echo -e "${YELLOW} 16.${NC} 安装 Komari Agent (默认 1.1.93)"
    echo -e "${YELLOW} 17.${NC} 安装 XrayR v0.9.4"
    echo -e "${YELLOW} 18.${NC} 安装 v2node v1.0.0"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${YELLOW} 19.${NC} ${RED}卸载并删除本脚本${NC}"
    echo -e "${RED} 0.${NC} 退出脚本 (或双击回车)${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# systemd 开机任务仅应用已保存的 IPv4 设置，不进入交互菜单或联网更新。
if [[ ${1:-} == "--apply-preferred-ipv4" ]]; then
    apply_saved_preferred_ipv4
    exit $?
fi

# 脚本运行初始化
record_usage_count
check_base_dependencies
check_script_update

while true; do
    show_menu
    read -r -p "请输入对应数字进行操作: " choice
    
    if [[ -z "$choice" ]]; then
        ((empty_count++))
        [[ $empty_count -ge 2 ]] && exit 0
        continue
    else
        empty_count=0
    fi

    case $choice in
        1)
            run_remote_script "${VENDOR_RAW_URL}/scripts/bench.sh" || error "系统测试脚本执行失败。"
            pause_menu
            ;;
        2)
            passwd root || error "root 密码修改失败。"
            pause_menu
            ;;
        3)
            CURRENT_SSH_PORT=$(awk 'tolower($1) == "port" {print $2; exit}' /etc/ssh/sshd_config)
            [ -z "$CURRENT_SSH_PORT" ] && CURRENT_SSH_PORT="22"
            echo -e "${BLUE}当前端口: ${YELLOW}${CURRENT_SSH_PORT}${NC}"
            read -r -p "继续修改？(y/n): " confirm_ssh
            if [[ $confirm_ssh == [yY] ]]; then
                read -r -p "新端口 (默认 $DEFAULT_PORT): " ssh_port
                ssh_port=${ssh_port:-$DEFAULT_PORT}
                if ! valid_port "$ssh_port"; then
                    error "端口必须是 1-65535 之间的整数。"
                else
                    ssh_backup=$(mktemp /tmp/sshd_config.XXXXXX)
                    cp /etc/ssh/sshd_config "$ssh_backup"
                    if grep -Eiq '^[[:space:]#]*Port[[:space:]]+' /etc/ssh/sshd_config; then
                        sed -i -E "0,/^[[:space:]#]*Port[[:space:]]+.*/s//Port $ssh_port/" /etc/ssh/sshd_config
                    else
                        echo "Port $ssh_port" >> /etc/ssh/sshd_config
                    fi

                    if sshd -t && (systemctl restart ssh || systemctl restart sshd); then
                        info "SSH 端口已成功修改为 $ssh_port。"
                    else
                        cp "$ssh_backup" /etc/ssh/sshd_config
                        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
                        error "SSH 配置检查或服务重启失败，已恢复原配置。"
                    fi
                    rm -f "$ssh_backup"
                fi
            fi
            pause_menu
            ;;
        4)
            enable_bbr || error "BBR 安装或启用失败。"
            pause_menu
            ;;
        5)
            check_installed "iperf3" "iperf3 测速工具" "iperf3" || { pause_menu; continue; }
            install_status=1
            if command_exists yum && ! command_exists dnf; then
                yum install -y epel-release && install_packages iperf3 && install_status=0
            elif command_exists apt-get || command_exists dnf || command_exists apk; then
                install_packages iperf3 && install_status=0
            else
                error "不支持当前系统的包管理器。"
            fi

            if (( install_status == 0 )) && command_exists iperf3; then
                echo -e "${GREEN}安装完成！${NC}"
                echo -e "仅本机监听: ${RED}iperf3 -s -B 127.0.0.1${NC}"
                echo -e "公网测速时运行: ${RED}iperf3 -s${NC}，并在防火墙中仅允许测速客户端 IP。"
            else
                error "iperf3 安装失败，请根据上方错误检查软件源。"
            fi
            pause_menu
            ;;
        6)
            public_ipv4_menu
            ;;
        7 | 8)
            ver="11" && [[ "$choice" == "8" ]] && ver="12"
            warn "警告：重装系统会清空当前服务器数据。"
            read -r -p "确认重装 Debian $ver？请输入 YES 继续: " reinstall_confirm
            [[ $reinstall_confirm == "YES" ]] || continue
            check_dd_dependencies || {
                error "DD 依赖安装失败，已取消重装。"
                pause_menu
                continue
            }
            read -r -p "设置 Debian $ver 密码 (默认 $DEFAULT_PASS): " dd_pass
            dd_pass=${dd_pass:-$DEFAULT_PASS}
            run_remote_script "${VENDOR_RAW_URL}/scripts/veip007-InstallNET.sh" \
                -d "$ver" -v 64 -a -p "$dd_pass" ||
                error "Debian $ver 重装脚本下载或执行失败。"
            ;;
        9)
            warn "警告：重装系统会清空当前服务器数据。"
            read -r -p "确认重装 Windows 10 LTSC？请输入 YES 继续: " reinstall_confirm
            [[ $reinstall_confirm == "YES" ]] || continue
            check_dd_dependencies || {
                error "DD 依赖安装失败，已取消重装。"
                pause_menu
                continue
            }
            read -r -p "设置 Win10 密码 (默认 $DEFAULT_PASS): " win_pass
            win_pass=${win_pass:-$DEFAULT_PASS}
            run_remote_script "${VENDOR_RAW_URL}/scripts/minlearn-inst.sh" \
                -w "$win_pass" \
                -t "$WIN10_LTSC_IMAGE_URL" ||
                error "Windows 10 LTSC 重装脚本下载或执行失败。"
            ;;
        10)
            warn "警告：重装系统会清空当前服务器数据。"
            read -r -p "确认打开 veip007 旧版 Windows DD 交互脚本？请输入 YES 继续: " reinstall_confirm
            [[ $reinstall_confirm == "YES" ]] || continue
            check_dd_dependencies || {
                error "DD 依赖安装失败，已取消重装。"
                pause_menu
                continue
            }
            warn "上游可选 Win7 与 Windows Server 2008 R2/2012 R2/2016/2019，不含 Win10/Win11。"
            warn "请在上游交互菜单中选择镜像并确认其默认密码。"
            run_remote_script "${VENDOR_RAW_URL}/scripts/veip007-dd-od.sh" ||
                error "veip007 Windows DD 脚本下载或执行失败。"
            ;;
        11)
            check_windows_x86_requirements || {
                pause_menu
                continue
            }
            warn "警告：重装系统会清空当前服务器数据。"
            warn "该 Windows 11 LTSC 镜像仅适用于 x86_64 服务器。"
            read -r -p "确认重装 Windows 11 LTSC？请输入 YES 继续: " reinstall_confirm
            [[ $reinstall_confirm == "YES" ]] || continue
            check_dd_dependencies || {
                error "DD 依赖安装失败，已取消重装。"
                pause_menu
                continue
            }
            read -r -p "设置 Win11 密码 (默认 $DEFAULT_PASS): " win_pass
            win_pass=${win_pass:-$DEFAULT_PASS}
            run_remote_script "${VENDOR_RAW_URL}/scripts/minlearn-inst.sh" \
                -w "$win_pass" \
                -t "$WIN11_LTSC_IMAGE_URL" ||
                error "Windows 11 LTSC 重装脚本下载或执行失败。"
            ;;
        12)
            check_installed "bt" "aaPanel 面板" "bt" || { pause_menu; continue; }
            panel_url="${VENDOR_RAW_URL}/scripts/mzwrt-aapanel-install.sh"
            warn "即将安装第三方备份版 aaPanel。"
            if run_remote_script_with_input "yes" "$panel_url" -y &&
                [[ -d /www/server/panel ]] &&
                command_exists bt; then
                info "aaPanel 安装完成。管理命令: bt"
                warn "aaPanel 会自行创建面板监听端口；请在面板安全设置和云防火墙中限制访问 IP。"
            else
                error "aaPanel 安装失败；如果官方地址处于维护状态，请稍后重试。"
            fi
            show_mini_header
            ;;
        13)
            check_installed "docker" "Docker" "docker ps" || { pause_menu; continue; }
            if check_docker; then
                info "Docker 安装完成并已正常运行。"
            fi
            pause_menu
            ;;
        14)
            check_docker || { pause_menu; continue; }
            if docker ps -a --format '{{.Names}}' | grep -q "^status$"; then
                read -r -p "探针容器已存在，是否重装？(y/n): " re_status
                [[ $re_status != [yY] ]] && continue
                docker rm -f status >/dev/null || {
                    error "旧 status 容器删除失败。"
                    pause_menu
                    continue
                }
            fi
            read -r -p "探针内部监听端口 (默认 $DEFAULT_PORT): " s_port
            s_port=${s_port:-$DEFAULT_PORT}
            if ! valid_port "$s_port"; then
                error "监听端口必须是 1-65535 之间的整数。"
                pause_menu
                continue
            fi
            if ! download_file \
                "${VENDOR_RAW_URL}/configs/serverstatus-config.json" \
                "$HOME/serverstatus-config.json"; then
                pause_menu
                continue
            fi
            if ! grep -q '^[[:space:]]*{' "$HOME/serverstatus-config.json"; then
                error "ServerStatus 配置文件格式无效。"
                pause_menu
                continue
            fi
            choose_service_bind_ip "ServerStatus 的 35601 端口用于客户端上报；只有跨服务器监控时才需要公网监听。"
            mkdir -p "$HOME/serverstatus-monthtraffic"
            if docker run -d --restart=always --name=status \
                -v "$HOME/serverstatus-config.json:/ServerStatus/server/config.json" \
                -v "$HOME/serverstatus-monthtraffic:/usr/share/nginx/html/json" \
                -p "${BIND_IP}:${s_port}:80" \
                -p "${SERVICE_BIND_IP}:35601:35601" \
                cppla/serverstatus:server >/dev/null &&
                wait_for_container status; then
                info "探针安装完成！反代目标: http://127.0.0.1:${s_port}"
                if [[ $SERVICE_BIND_IP == "$BIND_IP" ]]; then
                    echo -e "客户端接入地址: ${BLUE}127.0.0.1:35601${NC}（仅本机）"
                else
                    echo -e "客户端接入端口: ${BLUE}35601${NC}（公网监听，请限制来源 IP）"
                fi
            else
                error "ServerStatus 容器创建或启动失败。"
                docker logs --tail 30 status 2>/dev/null || true
            fi
            pause_menu
            ;;
        15)
            read -r -p "监听端口 (默认 25774): " k_port
            k_port=${k_port:-25774}
            if ! valid_port "$k_port"; then
                error "端口必须是 1-65535 之间的整数。"
                pause_menu
                continue
            fi
            if [[ -x /opt/komari/komari ]]; then
                read -r -p "检测到 Komari，是否重新安装？(y/n, 默认n): " re_k
                [[ $re_k == [yY] ]] || continue
            fi
            if run_remote_script "$KOMARI_INSTALL_URL" --port "$k_port"; then
                info "Komari 1.2.0 安装完成。"
                echo -e "访问地址: ${BLUE}http://服务器IP:${k_port}${NC}"
                echo -e "管理命令: ${BLUE}systemctl status komari${NC}"
            else
                error "Komari 安装失败。"
            fi
            pause_menu
            ;;
        16)
            if [[ -x /opt/komari/agent ]]; then
                read -r -p "检测到 Komari Agent，是否重新安装？(y/n, 默认n): " re_agent
                [[ $re_agent == [yY] ]] || continue
            fi
            read -r -p "Agent 版本 (默认 1.1.93，可选 1.2.0): " agent_version
            agent_version=${agent_version:-1.1.93}
            case "$agent_version" in
                1.1.93|1.93) agent_version="1.1.93" ;;
                1.2.0|1.20) agent_version="1.2.0" ;;
                *)
                    error "仅支持 1.1.93 和 1.2.0。"
                    pause_menu
                    continue
                    ;;
            esac
            read -r -p "面板地址: " agent_endpoint
            read -r -s -p "Agent Token: " agent_token
            echo
            if [[ -z "$agent_endpoint" || -z "$agent_token" ]]; then
                error "面板地址和 Token 不能为空。"
                unset agent_token
                pause_menu
                continue
            fi
            if run_remote_script "$KOMARI_AGENT_INSTALL_URL" \
                --install-version "$agent_version" \
                -e "$agent_endpoint" -t "$agent_token" \
                --disable-web-ssh --disable-auto-update --ignore-unsafe-cert; then
                info "Komari Agent ${agent_version} 安装完成。"
                echo -e "管理命令: ${BLUE}systemctl status komari-agent${NC}"
            else
                error "Komari Agent 安装失败。"
            fi
            unset agent_token
            pause_menu
            ;;
        17)
            check_installed "xrayr" "XrayR v0.9.4" "xrayr" || { pause_menu; continue; }
            if run_remote_script "$XRAYR_INSTALL_URL"; then
                if command_exists xrayr && [[ -f /etc/systemd/system/XrayR.service ]]; then
                    info "XrayR v0.9.4 安装完成。管理命令: xrayr"
                else
                    error "安装脚本已结束，但未检测到 XrayR 管理命令或服务文件。"
                fi
            else
                error "XrayR 安装失败。"
            fi
            show_mini_header
            ;;
        18)
            check_installed "v2node" "v2node v1.0.0" "v2node" || { pause_menu; continue; }
            read -r -p "面板 API 地址 (例如 https://example.com/，留空则只安装程序): " v2_api_host
            read -r -p "节点 ID (留空则只安装程序): " v2_node_id
            read -r -s -p "节点通讯密钥 (留空则只安装程序): " v2_api_key
            echo

            v2_args=()
            if [[ -n "$v2_api_host" || -n "$v2_node_id" || -n "$v2_api_key" ]]; then
                if [[ -z "$v2_api_host" || -z "$v2_node_id" || -z "$v2_api_key" || ! "$v2_node_id" =~ ^[0-9]+$ ]]; then
                    error "v2node 配置参数不完整或节点 ID 非数字，已取消安装。"
                    pause_menu
                    continue
                fi
                v2_args=(--api-host "$v2_api_host" --node-id "$v2_node_id" --api-key "$v2_api_key")
            fi

            if run_remote_script "$V2NODE_INSTALL_URL" "${v2_args[@]}"; then
                if command_exists v2node; then
                    info "v2node v1.0.0 安装完成。管理命令: v2node"
                    if [[ ! -f /etc/v2node/config.json ]]; then
                        warn "v2node 已安装，但尚未生成 /etc/v2node/config.json；请执行 v2node generate 或重新运行本菜单填写面板参数。"
                    elif command_exists systemctl && systemctl is-active --quiet v2node; then
                        info "v2node 服务正在运行。"
                    else
                        warn "v2node 配置文件已存在，但服务尚未运行，请检查配置后执行: v2node start"
                    fi
                else
                    error "安装脚本已结束，但未检测到 v2node 管理命令。"
                fi
            else
                error "v2node 安装失败。"
            fi
            unset v2_api_key
            show_mini_header
            ;;
        19)
            read -r -p "确定要删除本脚本及快捷命令吗？(y/n): " del_confirm
            if [[ $del_confirm == [yY] ]]; then
                remove_preferred_ipv4_persistence 1
                rm -f "$UPDATE_REVISION_FILE"
                rmdir "$TOOL_STATE_DIR" 2>/dev/null || true
                rm -f "/usr/local/bin/${SHORTCUT_CMD}"
                echo -e "${GREEN}快捷命令已删除。${NC}"
                rm -f "$0"
                echo -e "${GREEN}脚本文件已删除。再见！${NC}"
                exit 0
            fi
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}选择无效。${NC}"; sleep 1 ;;
    esac
done
