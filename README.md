# 一个人的脚本百宝箱

一个面向 Linux VPS 的交互式运维脚本，集合常用系统设置、网络测试、系统重装和服务部署功能。

## 主要功能

- 系统工具：查看系统信息与性能测试、修改 root 密码、修改 SSH 端口、启用 BBR、安装 iperf3。
- 系统重装：安装 Debian 11、Debian 12、Windows 10 LTSC，或使用交互脚本选择 Windows 镜像。
- 服务部署：安装 aaPanel 、Docker、ServerStatus 和 Komari。
- 节点后端：安装 XrayR 和 v2node。
- 脚本管理：自动检查更新，以及卸载脚本和快捷命令。

## 使用方法

请使用 `root` 用户执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Taylor000/tool/master/tool.sh -o /usr/local/bin/tool
chmod +x /usr/local/bin/tool
tool
```

