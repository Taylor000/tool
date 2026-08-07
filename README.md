# 一个人的脚本百宝箱

一个面向 Linux VPS 的交互式运维脚本，集合常用系统设置、网络测试、系统重装和服务部署功能。

## 主要功能

- 系统工具：查看系统信息与性能测试、修改 root 密码、修改 SSH 端口、启用 BBR、安装 iperf3。
- 系统重装：安装 Debian 11、Debian 12、Windows 10 LTSC，或使用交互脚本选择 Windows 镜像。
- 服务部署：安装 aaPanel 、Docker、ServerStatus 和 Komari。
- 节点后端：安装 XrayR 和 v2node。
- 脚本管理：自动检查更新，以及卸载脚本和快捷命令。

## 菜单预览

```text
$ tool

==================================================
             一个人的脚本百宝箱
             快捷启动命令: tool
==================================================
 1. 显示系统基本信息与性能测试
 2. 修改系统 root 密码
 3. 修改 SSH 服务端口
 4. 安装 BBR 加速插件
 5. 安装 iperf3 网络测速工具
 6. 安装 Debian 11 系统（萌咖版）
 7. 安装 Debian 12 系统（萌咖版）
 8. 安装 Win10 LTSC 系统（秋水逸冰）
 9. 安装 Windows 系统（veip007 交互版）
10. 安装 aaPanel 面板（mzwrt 备份版）
11. 安装 Docker 运行环境
12. 安装 ServerStatus 监控探针
13. 安装 Komari 监控探针（Docker 版）
14. 安装 XrayR 官方版（v0.9.4，已停止维护）
15. 安装 XrayR 后端对接（柚子备份版，需配置）
16. 安装 v2node 后端对接（官方版）
--------------------------------------------------
17. 卸载并删除本脚本
 0. 退出脚本（或双击回车）
==================================================
```

## 使用方法

请使用 `root` 用户执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Taylor000/tool/master/tool.sh -o /usr/local/bin/tool
chmod +x /usr/local/bin/tool
tool
```
