<div align="center">
  <img src="./assets/header.svg" width="100%" alt="一个人的脚本百宝箱 — Linux VPS Toolbox" />
</div>

<br />

<div align="center">
  <samp>一只住在终端里的 Linux VPS 工具箱 ૮ ˶ᵔ ᵕ ᵔ˶ ა</samp>
  <br />
  <samp>把常用的系统设置、网络管理和服务部署，好好收进一个脚本里。</samp>
</div>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/version-v2.2.0-FDEBF3?style=flat-square&labelColor=FFF9F3" alt="Version 2.2.0" />
  <img src="https://img.shields.io/badge/Shell-EAF7F1?style=flat-square&logo=gnu-bash&logoColor=4F6F65" alt="Shell" />
  <img src="https://img.shields.io/badge/Linux-FFF2CF?style=flat-square&logo=linux&logoColor=75664A" alt="Linux" />
  <img src="https://img.shields.io/badge/IPv4-EAF2FF?style=flat-square&logo=icloud&logoColor=536684" alt="IPv4" />
</p>

## 工具箱里装了什么

- 🌷 系统信息、root 密码、SSH 端口、BBR 和 iperf3
- 🌐 多公网 IPv4 检测与默认出口切换
- 💿 Debian 与 Windows 系统重装
- 🧺 aaPanel、Docker、ServerStatus 和 Komari
- ✨ XrayR 与 v2node 节点后端
- 🔄 自动更新、卸载及快捷命令管理

## 快速开始

请使用 `root` 用户执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Taylor000/tool/master/tool.sh -o /usr/local/bin/tool
chmod +x /usr/local/bin/tool
tool
```

## 菜单

```text
 1. 系统信息与性能测试
 2. 修改 root 密码
 3. 修改 SSH 端口
 4. 安装 BBR
 5. 安装 iperf3
 6. 公网 IPv4 与默认出口管理
 7-11. 系统重装
12-15. 服务部署
16-18. 节点后端
19. 卸载脚本
 0. 退出
```

## 公网 IPv4 默认出口

菜单 `6` 会列出网卡绑定的公网 IPv4，并显示当前默认网卡、内核首选源 IP、外部实际出口和永久设置状态。

- **临时切换**：立即生效，重启或重载网络后可能失效。
- **永久切换**：验证成功后通过 systemd 在开机联网时重新应用。
- **取消永久设置**：移除开机配置，不改变当前出口。

> 目前仅处理 IPv4，并只允许切换当前默认网卡上的地址。切换前后都会验证公网出口，失败时自动恢复；存在 NAT/SNAT 且出口不匹配时会拒绝切换。

## 小提醒

- DD 重装会清空服务器数据，请提前备份。
- Windows 11 LTSC 仅支持 `x86_64`。
- XrayR 官方版已停止维护，仅建议用于旧节点兼容。

---

<div align="center">
  <sub>把重复的操作交给脚本，把时间留给更有趣的事情 ♡</sub>
  <br />
  <sub>Made with care by <a href="https://github.com/Taylor000">Taylor000</a></sub>
</div>
