#!/bin/bash

set -o pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
vendor_release_url="https://github.com/Taylor000/tool/releases/latest/download"

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

########################
# 参数解析
########################
VERSION_ARG=""
API_HOST_ARG=""
NODE_ID_ARG=""
API_KEY_ARG=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-host)
                API_HOST_ARG="$2"; shift 2 ;;
            --node-id)
                NODE_ID_ARG="$2"; shift 2 ;;
            --api-key)
                API_KEY_ARG="$2"; shift 2 ;;
            -h|--help)
                echo "用法: $0 [版本号] [--api-host URL] [--node-id ID] [--api-key KEY]"
                exit 0 ;;
            --*)
                echo "未知参数: $1"; exit 1 ;;
            *)
                # 兼容第一个位置参数作为版本号
                if [[ -z "$VERSION_ARG" ]]; then
                    VERSION_ARG="$1"; shift
                else
                    shift
                fi ;;
        esac
    done
}

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    # 优化版本：批量检查和安装包，减少系统调用
    need_install_apt() {
        local packages=("$@")
        local missing=()
        local p

        for p in "${packages[@]}"; do
            if ! dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null | grep -q '^ii'; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "安装缺失的包: ${missing[*]}"
            if ! apt-get update; then
                echo -e "${red}APT 软件包索引更新失败，请检查软件源和网络。${plain}" >&2
                return 1
            fi
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
                echo -e "${red}依赖安装失败: ${missing[*]}${plain}" >&2
                return 1
            fi
        fi
    }

    need_install_yum() {
        local packages=("$@")
        local missing=()
        local p
        
        # 批量检查已安装的包
        local installed_list
        installed_list=$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "安装缺失的包: ${missing[*]}"
            if ! yum install -y "${missing[@]}"; then
                echo -e "${red}依赖安装失败: ${missing[*]}${plain}" >&2
                return 1
            fi
        fi
    }

    need_install_apk() {
        local packages=("$@")
        local missing=()
        local p
        
        # 批量检查已安装的包
        local installed_list
        installed_list=$(apk info 2>/dev/null | sort)
        
        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "安装缺失的包: ${missing[*]}"
            if ! apk add --no-cache "${missing[@]}"; then
                echo -e "${red}依赖安装失败: ${missing[*]}${plain}" >&2
                return 1
            fi
        fi
    }

    # 一次性安装所有必需的包
    if [[ x"${release}" == x"centos" ]]; then
        # 检查并安装 epel-release
        if ! rpm -q epel-release >/dev/null 2>&1; then
            echo "安装 EPEL 源..."
            yum install -y epel-release || return 1
        fi
        need_install_yum wget curl unzip tar cronie socat ca-certificates || return 1
        update-ca-trust force-enable >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"alpine" ]]; then
        need_install_apk wget curl unzip tar socat ca-certificates || return 1
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"debian" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates || return 1
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"ubuntu" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates || return 1
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"arch" ]]; then
        echo "更新包数据库..."
        pacman -Sy --noconfirm || return 1
        # --needed 会跳过已安装的包，非常高效
        echo "安装必需的包..."
        pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates || return 1
    else
        echo -e "${red}不支持当前系统，无法安装依赖。${plain}" >&2
        return 1
    fi

    local required_command
    for required_command in curl unzip tar socat; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            echo -e "${red}依赖安装完成后仍找不到命令: ${required_command}${plain}" >&2
            return 1
        fi
    done
}

download_v2node_archive() {
    local url="$1"
    local destination="$2"
    local partial="${destination}.part"

    rm -f "$partial" "$destination"
    if ! curl --fail --location --show-error --progress-bar \
        --connect-timeout 15 --max-time 900 --retry 3 --retry-delay 2 \
        --output "$partial" "$url"; then
        echo -e "${red}下载 v2node 失败: ${url}${plain}" >&2
        rm -f "$partial"
        return 1
    fi

    if [[ ! -s "$partial" ]]; then
        echo -e "${red}下载的 v2node 压缩包为空。${plain}" >&2
        rm -f "$partial"
        return 1
    fi
    if ! unzip -tq "$partial" >/dev/null; then
        echo -e "${red}下载结果不是有效的 v2node ZIP 压缩包。${plain}" >&2
        rm -f "$partial"
        return 1
    fi

    mv -f "$partial" "$destination"
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service v2node status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status v2node | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

generate_v2node_config() {
        local api_host="$1"
        local node_id="$2"
        local api_key="$3"

        mkdir -p /etc/v2node >/dev/null 2>&1
        cat > /etc/v2node/config.json <<EOF
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${node_id},
            "ApiKey": "${api_key}",
            "Timeout": 15
        }
    ]
}
EOF
        echo -e "${green}V2node 配置文件生成完成,正在重新启动服务${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node restart
        else
            systemctl restart v2node
        fi
        sleep 2
        echo -e ""
        if check_status; then
            echo -e "${green}v2node 重启成功${plain}"
        else
            echo -e "${red}v2node 可能启动失败，请使用 v2node log 查看日志信息${plain}"
        fi
}

install_v2node() {
    local version_param="${1:-}"
    local release_tag url work_dir archive extract_dir payload_dir
    local install_dir="/usr/local/v2node"
    local backup_dir="/usr/local/v2node.backup.$$"

    if [[ -z "$version_param" ]]; then
        last_version="Taylor000/tool latest"
        echo -e "${green}使用 Taylor000/tool latest release 中的 v2node，开始安装...${plain}"
        url="${vendor_release_url}/v2node-linux-${arch}.zip"
    else
        release_tag="$version_param"
        [[ "$release_tag" == v* ]] || release_tag="v${release_tag}"
        last_version="$release_tag"
        echo -e "${green}使用 Taylor000/tool ${release_tag} release 中的 v2node，开始安装...${plain}"
        url="https://github.com/Taylor000/tool/releases/download/${release_tag}/v2node-linux-${arch}.zip"
    fi

    work_dir=$(mktemp -d /tmp/v2node-install.XXXXXX) || {
        echo -e "${red}无法创建临时安装目录。${plain}" >&2
        return 1
    }
    archive="${work_dir}/v2node-linux.zip"
    extract_dir="${work_dir}/payload"
    mkdir -p "$extract_dir"

    if ! download_v2node_archive "$url" "$archive"; then
        rm -rf "$work_dir"
        return 1
    fi
    if ! unzip -q "$archive" -d "$extract_dir"; then
        echo -e "${red}解压 v2node 失败，原有安装未被修改。${plain}" >&2
        rm -rf "$work_dir"
        return 1
    fi

    payload_dir=$(dirname "$(find "$extract_dir" -type f -name v2node -print -quit)")
    if [[ -z "$payload_dir" || "$payload_dir" == "." ]]; then
        echo -e "${red}压缩包中缺少 v2node 可执行文件，原有安装未被修改。${plain}" >&2
        rm -rf "$work_dir"
        return 1
    fi
    local required_file
    for required_file in v2node geoip.dat geosite.dat; do
        if [[ ! -f "${payload_dir}/${required_file}" ]]; then
            echo -e "${red}压缩包缺少文件: ${required_file}，原有安装未被修改。${plain}" >&2
            rm -rf "$work_dir"
            return 1
        fi
    done

    rm -rf "$backup_dir"
    if [[ -e "$install_dir" ]]; then
        if ! mv "$install_dir" "$backup_dir"; then
            echo -e "${red}无法备份现有 v2node 安装。${plain}" >&2
            rm -rf "$work_dir"
            return 1
        fi
    fi
    if ! mkdir -p "$install_dir" || ! cp -a "${payload_dir}/." "${install_dir}/"; then
        echo -e "${red}写入 v2node 安装目录失败，正在恢复旧版本。${plain}" >&2
        rm -rf "$install_dir"
        [[ -e "$backup_dir" ]] && mv "$backup_dir" "$install_dir"
        rm -rf "$work_dir"
        return 1
    fi
    if ! chmod +x "${install_dir}/v2node"; then
        echo -e "${red}无法设置 v2node 执行权限，正在恢复旧版本。${plain}" >&2
        rm -rf "$install_dir"
        [[ -e "$backup_dir" ]] && mv "$backup_dir" "$install_dir"
        rm -rf "$work_dir"
        return 1
    fi
    rm -rf "$backup_dir" "$work_dir"
    cd "$install_dir" || return 1

    mkdir /etc/v2node/ -p
    cp geoip.dat /etc/v2node/
    cp geosite.dat /etc/v2node/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/v2node -f
        cat <<EOF > /etc/init.d/v2node
#!/sbin/openrc-run

name="v2node"
description="v2node"

command="/usr/local/v2node/v2node"
command_args="server"
command_user="root"

pidfile="/run/v2node.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/v2node
        rc-update add v2node default
        echo -e "${green}v2node ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/v2node.service -f
        cat <<EOF > /etc/systemd/system/v2node.service
[Unit]
Description=v2node Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2node/
ExecStart=/usr/local/v2node/v2node server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop v2node
        systemctl enable v2node
        echo -e "${green}v2node ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f /etc/v2node/config.json ]]; then
        # 如果通过 CLI 传入了完整参数，则直接生成配置并跳过交互
        if [[ -n "$API_HOST_ARG" && -n "$NODE_ID_ARG" && -n "$API_KEY_ARG" ]]; then
            generate_v2node_config "$API_HOST_ARG" "$NODE_ID_ARG" "$API_KEY_ARG"
            echo -e "${green}已根据参数生成 /etc/v2node/config.json${plain}"
            first_install=false
        else
            first_install=true
        fi
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node start
        else
            systemctl start v2node
        fi
        sleep 2
        echo -e ""
        if check_status; then
            echo -e "${green}v2node 重启成功${plain}"
        else
            echo -e "${red}v2node 可能启动失败，请使用 v2node log 查看日志信息${plain}"
        fi
        first_install=false
    fi

    local management_script
    management_script=$(mktemp /tmp/v2node-manager.XXXXXX) || return 1
    if ! curl --fail --location --silent --show-error --retry 3 \
        --output "$management_script" \
        https://raw.githubusercontent.com/Taylor000/tool/master/vendor/scripts/v2node/v2node.sh; then
        echo -e "${red}v2node 管理脚本下载失败。${plain}" >&2
        rm -f "$management_script"
        return 1
    fi
    if ! bash -n "$management_script"; then
        echo -e "${red}下载的 v2node 管理脚本语法无效。${plain}" >&2
        rm -f "$management_script"
        return 1
    fi
    chmod 755 "$management_script"
    mv -f "$management_script" /usr/bin/v2node

    cd "$cur_dir" || return 1
    rm -f install.sh
    echo "------------------------------------------"
    echo -e "管理脚本使用方法: "
    echo "------------------------------------------"
    echo "v2node              - 显示管理菜单 (功能更多)"
    echo "v2node start        - 启动 v2node"
    echo "v2node stop         - 停止 v2node"
    echo "v2node restart      - 重启 v2node"
    echo "v2node status       - 查看 v2node 状态"
    echo "v2node enable       - 设置 v2node 开机自启"
    echo "v2node disable      - 取消 v2node 开机自启"
    echo "v2node log          - 查看 v2node 日志"
    echo "v2node generate     - 生成 v2node 配置文件"
    echo "v2node update       - 更新 v2node"
    echo "v2node update x.x.x - 更新 v2node 指定版本"
    echo "v2node install      - 安装 v2node"
    echo "v2node uninstall    - 卸载 v2node"
    echo "v2node version      - 查看 v2node 版本"
    echo "------------------------------------------"
    curl -fsS --max-time 10 "https://api.v-50.me/counter" || true

    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装 v2node，是否自动生成 /etc/v2node/config.json？(y/n): " if_generate
        if [[ "$if_generate" =~ ^[Yy]$ ]]; then
            # 交互式收集参数，提供示例默认值
            read -rp "面板API地址[格式: https://example.com/]: " api_host
            api_host=${api_host:-https://example.com/}
            read -rp "节点ID: " node_id
            node_id=${node_id:-1}
            read -rp "节点通讯密钥: " api_key

            # 生成配置文件（覆盖可能从包中复制的模板）
            generate_v2node_config "$api_host" "$node_id" "$api_key"
        else
            echo "${green}已跳过自动生成配置。如需后续生成，可执行: v2node generate${plain}"
        fi
    fi
}

parse_args "$@"
echo -e "${green}开始安装${plain}"
if ! install_base; then
    echo -e "${red}基础依赖安装失败，v2node 安装已停止。${plain}" >&2
    exit 1
fi
if ! install_v2node "$VERSION_ARG"; then
    echo -e "${red}v2node 安装失败。${plain}" >&2
    exit 1
fi
