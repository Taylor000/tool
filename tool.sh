#!/usr/bin/env bash

set -o pipefail

# 自动修复 Windows 换行符问题
sed -i 's/\r$//' "$0" 2>/dev/null

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

# 默认全局配置
DEFAULT_PORT="11156"
DEFAULT_PASS="github.taylor000"
BIND_IP="127.0.0.1"
PUBLIC_BIND_IP="0.0.0.0"

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

show_apt_source_hint() {
    local bad_sources
    bad_sources=$(grep -RhsE '^[[:space:]]*deb .*-(backports|updates|security)' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)
    if [[ -n "$bad_sources" ]]; then
        warn "检测到以下扩展软件源，请检查其中是否包含已停止维护的发行版："
        printf '%s\n' "$bad_sources"
    fi
}

update_package_index() {
    if command_exists apt-get; then
        if ! apt-get update; then
            error "APT 软件源更新失败，安装已停止。"
            show_apt_source_hint
            return 1
        fi
    elif command_exists dnf; then
        dnf makecache || {
            error "DNF 软件源更新失败。"
            return 1
        }
    elif command_exists yum; then
        yum makecache || {
            error "YUM 软件源更新失败。"
            return 1
        }
    elif command_exists apk; then
        apk update || {
            error "APK 软件源更新失败。"
            return 1
        }
    else
        error "无法识别包管理器。"
        return 1
    fi
}

install_packages() {
    (( $# > 0 )) || return 0

    if command_exists apt-get; then
        update_package_index || return 1
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
            --connect-timeout 15 --retry 2 \
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
    command_exists curl || missing+=(curl)
    command_exists wget || missing+=(wget)

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
    download_script "https://raw.githubusercontent.com/teddysun/across/master/bbr.sh" "$bbr_script" &&
        bash "$bbr_script"
    local status=$?
    rm -f "$bbr_script"
    return "$status"
}

# 检查并自动安装 Docker
check_docker() {
    if ! command_exists docker; then
        warn "检测到系统未安装 Docker，正在开始自动安装..."
        run_remote_script "https://get.docker.com" || {
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
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}             ${SCRIPT_NAME}                  ${NC}"
    echo -e "${BLUE}     Author: ${YELLOW}${AUTHOR_GITHUB}${NC}"
    echo -e "${BLUE}     快捷启动命令: ${RED}${SHORTCUT_CMD}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW} 1.${NC} 显示系统基本信息与性能测试"
    echo -e "${YELLOW} 2.${NC} 修改系统 root 密码"
    echo -e "${YELLOW} 3.${NC} 修改 SSH 服务端口"
    echo -e "${YELLOW} 4.${NC} 安装 BBR 加速插件"
    echo -e "${YELLOW} 5.${NC} 安装 iperf3 网络测速工具"
    echo -e "${YELLOW} 6.${NC} 安装 Debian 11 系统 (萌咖版)"
    echo -e "${YELLOW} 7.${NC} 安装 Debian 12 系统 (萌咖版)"
    echo -e "${YELLOW} 8.${NC} 安装 Win10 LTSC 系统 (秋水逸冰)"
    echo -e "${YELLOW} 9.${NC} 安装 Windows 系统 (veip007 交互版)"
    echo -e "${YELLOW} 10.${NC} 安装 aaPanel 面板 (mzwrt 备份版)"
    echo -e "${YELLOW} 11.${NC} 安装 aaPanel 面板 (官方正式版)"
    echo -e "${YELLOW} 12.${NC} 安装 Docker 运行环境"
    echo -e "${YELLOW} 13.${NC} 安装 Realm 端口转发工具"
    echo -e "${YELLOW} 14.${NC} 安装 ServerStatus 监控探针"
    echo -e "${YELLOW} 15.${NC} 安装 Komari 监控探针 (Docker版)"
    echo -e "${YELLOW} 16.${NC} 安装 Xray 代理服务 (233boy版)"
    echo -e "${YELLOW} 17.${NC} 安装 3X-UI 面板 (Docker版)"
    echo -e "${YELLOW} 18.${NC} ${RED}XrayR 官方版 (项目已废弃)${NC}"
    echo -e "${YELLOW} 19.${NC} 安装 XrayR 后端对接 (柚子备份版)"
    echo -e "${YELLOW} 20.${NC} 安装 v2node 后端对接 (官方版)"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${YELLOW} 21.${NC} ${RED}卸载并删除本脚本${NC}"
    echo -e "${RED} 0.${NC} 退出脚本 (或双击回车)${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# 脚本运行初始化
check_base_dependencies

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
            run_remote_script "https://bench.sh" || error "系统测试脚本执行失败。"
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
            if command_exists apt-get; then
                install_packages iperf3 && install_status=0
            elif command_exists dnf; then
                dnf install -y iperf3 && install_status=0
            elif command_exists yum; then
                yum install -y epel-release &&
                    yum install -y iperf3 &&
                    install_status=0
            elif command_exists apk; then
                apk add --no-cache iperf3 && install_status=0
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
            read -r -p "设置 Debian $ver 密码 (默认 $DEFAULT_PASS): " dd_pass
            dd_pass=${dd_pass:-$DEFAULT_PASS}
            run_remote_script "https://raw.githubusercontent.com/veip007/dd/master/InstallNET.sh" \
                -d "$ver" -v 64 -a -p "$dd_pass" ||
                error "Debian $ver 重装脚本下载或执行失败。"
            ;;
        8)
            warn "警告：重装系统会清空当前服务器数据。"
            read -r -p "确认重装 Windows 10 LTSC？请输入 YES 继续: " reinstall_confirm
            [[ $reinstall_confirm == "YES" ]] || continue
            read -r -p "设置 Win10 密码 (默认 $DEFAULT_PASS): " win_pass
            win_pass=${win_pass:-$DEFAULT_PASS}
            run_remote_script "https://raw.githubusercontent.com/minlearn/inst/master/inst.sh" \
                -o "pass:$win_pass" \
                -t "https://dl.lamp.sh/vhd/zh-cn_windows10_ltsc.xz" ||
                error "Windows 10 LTSC 重装脚本下载或执行失败。"
            ;;
        9)
            warn "警告：重装系统会清空当前服务器数据。"
            read -r -p "确认打开 veip007 Windows DD 交互脚本？请输入 YES 继续: " reinstall_confirm
            [[ $reinstall_confirm == "YES" ]] || continue
            warn "请在上游交互菜单中选择 Windows 镜像并确认其默认密码。"
            run_remote_script "https://raw.githubusercontent.com/veip007/dd/master/dd-od.sh" ||
                error "veip007 Windows DD 脚本下载或执行失败。"
            ;;
        10 | 11)
            check_installed "bt" "aaPanel 面板" "bt" || { pause_menu; continue; }
            if [[ $choice == 10 ]]; then
                panel_url="https://raw.githubusercontent.com/mzwrt/aapanel-6.8.37-backup/main/install.sh"
                warn "即将安装第三方备份版 aaPanel。"
            else
                panel_url="https://www.aapanel.com/script/install_panel_en.sh"
            fi
            if run_remote_script "$panel_url" &&
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
            check_installed "realm" "Realm" "realm" || { pause_menu; continue; }
            run_remote_script "https://raw.githubusercontent.com/wcwq98/realm/refs/heads/main/realm.sh" ||
                error "Realm 安装脚本下载或执行失败。"
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
                "https://raw.githubusercontent.com/cppla/ServerStatus/master/server/config.json" \
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
            if docker ps -a --format '{{.Names}}' | grep -q "^${k_name}$"; then
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
        16)
            check_installed "xray" "Xray" "xray" || { pause_menu; continue; }
            if run_remote_script "https://raw.githubusercontent.com/233boy/Xray/main/install.sh"; then
                if command_exists xray; then
                    info "Xray 安装完成。管理命令: xray"
                else
                    error "安装脚本已结束，但未检测到 xray 管理命令。"
                fi
            else
                error "Xray 安装脚本下载或执行失败。"
            fi
            show_mini_header
            ;;
        17)
            check_docker || { pause_menu; continue; }
            read -r -p "设置 Docker 容器名称 (默认 3x-ui): " x_name
            x_name=${x_name:-3x-ui}
            read -r -p "设置面板映射端口 (默认 2053): " x_port
            x_port=${x_port:-2053}

            if ! valid_port "$x_port" || ! valid_container_name "$x_name"; then
                error "端口或容器名称格式无效。"
                pause_menu
                continue
            fi
            if docker ps -a --format '{{.Names}}' | grep -q "^${x_name}$"; then
                read -r -p "检测到名为 ${x_name} 的容器已存在，是否删除重装？(y/n): " re_x
                [[ $re_x != [yY] ]] && continue
                docker rm -f "$x_name" >/dev/null || {
                    error "旧容器删除失败。"
                    pause_menu
                    continue
                }
            fi

            x_data_dir="$HOME/3x-ui/db"
            x_cert_dir="$HOME/3x-ui/cert"
            mkdir -p "$x_data_dir" "$x_cert_dir"
            if docker run -d \
              --name "$x_name" \
              --cap-add NET_ADMIN \
              --cap-add NET_RAW \
              -p "${BIND_IP}:${x_port}:2053" \
              -e XUI_PORT=2053 \
              -e XUI_ENABLE_FAIL2BAN=true \
              -v "$x_data_dir:/etc/x-ui/" \
              -v "$x_cert_dir:/root/cert/" \
              --restart unless-stopped \
              ghcr.io/mhsanaei/3x-ui:latest >/dev/null &&
              wait_for_container "$x_name"; then
                info "3X-UI Docker 安装完成！"
                if [[ $BIND_IP == "127.0.0.1" ]]; then
                    echo -e "反向代理目标: ${BLUE}http://127.0.0.1:${x_port}${NC}"
                else
                    get_network_info || LOCAL_IP="服务器公网IP"
                    echo -e "访问地址: ${BLUE}http://${LOCAL_IP}:${x_port}${NC}"
                fi
                warn "面板会生成随机用户名、密码和访问路径，请查看容器日志："
                docker logs --tail 50 "$x_name" 2>&1
            else
                error "3X-UI 容器创建或启动失败。"
                docker logs --tail 30 "$x_name" 2>/dev/null || true
            fi
            show_mini_header
            ;;
        18)
            error "XrayR 官方仓库已明确标注“项目已废弃”，安装入口已经移除。"
            warn "如仍需兼容旧节点，请使用菜单 19 的备份版本，并自行评估安全风险。"
            pause_menu
            ;;
        19)
            check_installed "xrayr" "XrayR 柚子" "xrayr" || { pause_menu; continue; }
            if run_remote_script "https://raw.githubusercontent.com/youzi3/XrayR-script/main/install.sh"; then
                if command_exists xrayr || command_exists XrayR; then
                    info "XrayR 柚子版安装完成。管理命令: xrayr"
                else
                    error "安装脚本已结束，但未检测到 XrayR 管理命令。"
                fi
            else
                error "XrayR 柚子版安装脚本下载或执行失败。"
            fi
            show_mini_header
            ;;
        20)
            check_installed "v2node" "v2node" "v2node" || { pause_menu; continue; }
            if run_remote_script "https://raw.githubusercontent.com/wyx2685/v2node/master/script/install.sh"; then
                if command_exists v2node; then
                    info "v2node 安装完成。管理命令: v2node"
                    if command_exists systemctl && systemctl is-active --quiet v2node; then
                        info "v2node 服务正在运行。"
                    else
                        warn "v2node 已安装但服务尚未运行，请配置后执行: v2node start"
                    fi
                else
                    error "安装脚本已结束，但未检测到 v2node 管理命令。"
                fi
            else
                error "v2node 安装脚本下载或执行失败。"
            fi
            show_mini_header
            ;;
        21)
            read -r -p "确定要删除本脚本及快捷命令吗？(y/n): " del_confirm
            if [[ $del_confirm == [yY] ]]; then
                rm -f /usr/local/bin/${SHORTCUT_CMD}
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
