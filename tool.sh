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
SCRIPT_VERSION="2.1.16"
MIN_SUPPORTED_VERSION="2.1.4"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/Taylor000/tool/master/tool.sh"
VENDOR_RAW_URL="https://raw.githubusercontent.com/Taylor000/tool/master/vendor"
USAGE_COUNTER_URL="https://hits.sh/github.com/Taylor000/tool.svg?label=uses&color=blue"

# 默认全局配置
DEFAULT_PORT="11156"
DEFAULT_PASS="github.taylor000"
BIND_IP="127.0.0.1"
PUBLIC_BIND_IP="0.0.0.0"
APT_INDEX_REFRESHED=0
WIN10_LTSC_IMAGE_URL="https://dl.lamp.sh/vhd/zh-cn_windows10_ltsc.xz"
WIN11_LTSC_IMAGE_URL="https://dl.lamp.sh/vhd/zh-cn_win11_ltsc.xz"

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

check_script_update() {
    local remote_script remote_version remote_min_version answer force_update=0

    remote_script=$(mktemp /tmp/tool-update.XXXXXX) || return 0
    if ! download_script "${SCRIPT_RAW_URL}?t=$(date +%s)" "$remote_script"; then
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

    if [[ $(printf '%s\n%s\n' "$SCRIPT_VERSION" "$remote_version" | sort -V | tail -n 1) != "$remote_version" ||
          "$SCRIPT_VERSION" == "$remote_version" ]]; then
        rm -f "$remote_script"
        return 0
    fi

    if [[ -n "$remote_min_version" &&
          $(printf '%s\n%s\n' "$SCRIPT_VERSION" "$remote_min_version" | sort -V | head -n 1) == "$SCRIPT_VERSION" &&
          "$SCRIPT_VERSION" != "$remote_min_version" ]]; then
        force_update=1
    fi

    if (( force_update == 1 )); then
        error "当前版本 v${SCRIPT_VERSION} 低于最低支持版本 v${remote_min_version}，必须更新后才能继续。"
    else
        warn "发现新版本：${SCRIPT_VERSION} → ${remote_version}"
        read -r -p "是否立即更新并重新启动？(Y/n, 默认Y): " answer
        if [[ $answer =~ ^[Nn]$ ]]; then
            rm -f "$remote_script"
            return 0
        fi
    fi

    if ! install -m 755 "$remote_script" "$CURRENT_SCRIPT"; then
        error "脚本更新失败，当前版本未被替换。"
        rm -f "$remote_script"
        return 0
    fi
    rm -f "$remote_script"
    info "脚本已更新到 ${remote_version}，正在重新启动..."
    exec "$CURRENT_SCRIPT"
}

install_packages() {
    (( $# > 0 )) || return 0

    if command_exists apt-get; then
        if (( APT_INDEX_REFRESHED == 0 )); then
            warn "正在刷新 APT 软件包索引..."
            if DEBIAN_FRONTEND=noninteractive apt-get update; then
                APT_INDEX_REFRESHED=1
            else
                warn "APT 软件包索引刷新未完全成功，将尝试使用现有索引继续安装。"
            fi
        fi
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
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

run_remote_script() {
    local url=$1
    shift
    local script_file
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
    echo -e "${YELLOW} 6.${NC} 安装 Debian 11 系统 (萌咖版)"
    echo -e "${YELLOW} 7.${NC} 安装 Debian 12 系统 (萌咖版)"
    echo -e "${YELLOW} 8.${NC} 安装 Win10 LTSC 系统 (秋水逸冰)"
    echo -e "${YELLOW} 9.${NC} 安装旧版 Windows (veip007 交互版)"
    echo -e "${YELLOW} 10.${NC} 安装 Windows 11 LTSC 系统"
    echo -e "${YELLOW} 11.${NC} 安装 aaPanel 面板 (mzwrt 备份版)"
    echo -e "${YELLOW} 12.${NC} 安装 Docker 运行环境"
    echo -e "${YELLOW} 13.${NC} 安装 ServerStatus 监控探针"
    echo -e "${YELLOW} 14.${NC} 安装 Komari 监控探针 (Docker版)"
    echo -e "${YELLOW} 15.${NC} 安装 XrayR 官方版 (v0.9.4，已停止维护)"
    echo -e "${YELLOW} 16.${NC} 安装 XrayR 后端对接 (柚子备份版，需配置)"
    echo -e "${YELLOW} 17.${NC} 安装 v2node 后端对接 (官方版)"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${YELLOW} 18.${NC} ${RED}卸载并删除本脚本${NC}"
    echo -e "${RED} 0.${NC} 退出脚本 (或双击回车)${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

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
        6 | 7)
            ver="11" && [[ "$choice" == "7" ]] && ver="12"
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
        8)
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
        9)
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
        10)
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
        11)
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
        12)
            check_installed "docker" "Docker" "docker ps" || { pause_menu; continue; }
            if check_docker; then
                info "Docker 安装完成并已正常运行。"
            fi
            pause_menu
            ;;
        13)
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
        14)
            check_docker || { pause_menu; continue; }
            read -r -p "设置安装目录 (默认 $HOME/komari): " k_dir
            k_dir=${k_dir:-"$HOME/komari"}
            read -r -p "设置容器访问端口 (默认 25774): " k_port
            k_port=${k_port:-25774}
            read -r -p "设置 Docker 容器名称 (默认 komari): " k_name
            k_name=${k_name:-komari}

            if ! valid_port "$k_port" || ! valid_container_name "$k_name"; then
                error "端口或容器名称格式无效。"
                pause_menu
                continue
            fi
            if docker ps -a --format '{{.Names}}' | grep -Fxq "$k_name"; then
                read -r -p "检测到名为 ${k_name} 的容器已存在，是否删除重装？(y/n): " re_k
                [[ $re_k != [yY] ]] && continue
                docker rm -f "$k_name" >/dev/null || {
                    error "旧容器删除失败。"
                    pause_menu
                    continue
                }
            fi

            mkdir -p "$k_dir/data"
            if docker run -d \
              -p "${BIND_IP}:${k_port}:25774" \
              -v "$k_dir/data:/app/data" \
              --name "$k_name" \
              --restart unless-stopped \
              ghcr.io/komari-monitor/komari:latest >/dev/null &&
              wait_for_container "$k_name"; then
                info "Komari 安装完成！"
                if [[ $BIND_IP == "127.0.0.1" ]]; then
                    echo -e "反向代理目标: ${BLUE}http://127.0.0.1:${k_port}${NC}"
                else
                    get_network_info || LOCAL_IP="服务器公网IP"
                    echo -e "访问地址: ${BLUE}http://${LOCAL_IP}:${k_port}${NC}"
                fi
                warn "初始管理员账号和密码如下："
                docker logs --tail 30 "$k_name" 2>&1
            else
                error "Komari 容器创建或启动失败。"
                docker logs --tail 30 "$k_name" 2>/dev/null || true
            fi
            pause_menu
            ;;
        15)
            check_installed "xrayr" "XrayR 官方版" "xrayr" || { pause_menu; continue; }
            warn "XrayR 官方项目已停止维护，本入口固定安装最后的官方版本 v0.9.4。"
            warn "该版本不会再获得安全更新，请仅在兼容旧节点时使用。"
            read -r -p "是否继续安装？(y/n, 默认n): " xrayr_official_confirm
            if [[ $xrayr_official_confirm != [yY] ]]; then
                continue
            fi
            if run_remote_script "${VENDOR_RAW_URL}/scripts/xrayr-official-install.sh"; then
                if command_exists xrayr && [[ -f /etc/systemd/system/XrayR.service ]]; then
                    info "XrayR 官方版 v0.9.4 安装完成。管理命令: xrayr"
                    warn "请编辑 /etc/XrayR/config.yml 填写面板参数，然后执行: xrayr restart"
                else
                    error "安装脚本已结束，但未检测到 XrayR 管理命令或服务文件。"
                fi
            else
                error "XrayR 官方版安装脚本下载或执行失败。"
            fi
            show_mini_header
            ;;
        16)
            check_installed "xrayr" "XrayR 柚子" "xrayr" || { pause_menu; continue; }
            if run_remote_script "${VENDOR_RAW_URL}/scripts/youzi3-xrayr-install.sh"; then
                if command_exists xrayr || command_exists XrayR; then
                    info "XrayR 柚子版安装完成。管理命令: xrayr"
                    if [[ -f /etc/XrayR/config.yml ]]; then
                        warn "请先编辑 /etc/XrayR/config.yml 填写面板地址、节点 ID 和通讯密钥，然后执行: xrayr restart"
                    else
                        warn "未检测到 /etc/XrayR/config.yml，请执行 xrayr install 或重新运行本菜单。"
                    fi
                else
                    error "安装脚本已结束，但未检测到 XrayR 管理命令。"
                fi
            else
                error "XrayR 柚子版安装脚本下载或执行失败。"
            fi
            show_mini_header
            ;;
        17)
            check_installed "v2node" "v2node" "v2node" || { pause_menu; continue; }
            read -r -p "面板 API 地址 (例如 https://example.com/，留空则只安装程序): " v2_api_host
            read -r -p "节点 ID (留空则只安装程序): " v2_node_id
            read -r -p "节点通讯密钥 (留空则只安装程序): " v2_api_key

            v2_args=()
            if [[ -n "$v2_api_host" || -n "$v2_node_id" || -n "$v2_api_key" ]]; then
                if [[ -z "$v2_api_host" || -z "$v2_node_id" || -z "$v2_api_key" || ! "$v2_node_id" =~ ^[0-9]+$ ]]; then
                    error "v2node 配置参数不完整或节点 ID 非数字，已取消安装。"
                    pause_menu
                    continue
                fi
                v2_args=(--api-host "$v2_api_host" --node-id "$v2_node_id" --api-key "$v2_api_key")
            fi

            if run_remote_script "${VENDOR_RAW_URL}/scripts/wyx2685-v2node-install.sh" "${v2_args[@]}"; then
                if command_exists v2node; then
                    info "v2node 安装完成。管理命令: v2node"
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
                error "v2node 安装脚本下载或执行失败。"
            fi
            show_mini_header
            ;;
        18)
            read -r -p "确定要删除本脚本及快捷命令吗？(y/n): " del_confirm
            if [[ $del_confirm == [yY] ]]; then
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
