#!/usr/bin/env bash

set -o pipefail

url="https://raw.githubusercontent.com/Taylor000/XrayR/master/install.sh"
file=$(mktemp /tmp/xrayr-installer.XXXXXX) || exit 1
trap 'rm -f "$file"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 "$url" -o "$file" || exit 1
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$file" "$url" || exit 1
else
    echo "系统缺少 curl 或 wget。" >&2
    exit 1
fi

bash -n "$file" || exit 1
bash "$file" "$@"
