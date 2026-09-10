<div align="center">
  <img src="./assets/header.svg" width="100%" alt="一个人的脚本百宝箱 — Linux VPS Toolbox" />
</div>

<p align="center">
  <img src="https://img.shields.io/badge/version-v2.2.0-FDEBF3?style=flat-square&labelColor=FFF9F3" alt="Version 2.2.0" />
  <img src="https://img.shields.io/badge/Shell-EAF7F1?style=flat-square&logo=gnu-bash&logoColor=4F6F65" alt="Shell" />
  <img src="https://img.shields.io/badge/Linux-FFF2CF?style=flat-square&logo=linux&logoColor=75664A" alt="Linux" />
  <img src="https://img.shields.io/badge/IPv4-EAF2FF?style=flat-square&logo=icloud&logoColor=536684" alt="IPv4" />
</p>

## 使用

使用 `root` 用户执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Taylor000/tool/master/tool.sh -o /usr/local/bin/tool
chmod +x /usr/local/bin/tool
tool
```

## 菜单

```text
==================================================
             一个人的脚本百宝箱
     Author: https://github.com/Taylor000
     快捷启动命令: tool
     当前版本: v2.2.0  累计调用: 暂不可用
==================================================
 1. 显示系统基本信息与性能测试
 2. 修改系统 root 密码
 3. 修改 SSH 服务端口
 4. 安装 BBR 加速插件
 5. 安装 iperf3 网络测速工具
 6. 公网 IPv4 与默认出口管理
 7. 安装 Debian 11 系统 (萌咖版)
 8. 安装 Debian 12 系统 (萌咖版)
 9. 安装 Win10 LTSC 系统 (秋水逸冰)
 10. 安装旧版 Windows (veip007 交互版)
 11. 安装 Windows 11 LTSC 系统
 12. 安装 aaPanel 面板 (mzwrt 备份版)
 13. 安装 Docker 运行环境
 14. 安装 ServerStatus 监控探针
 15. 安装 Komari 监控探针 (Docker版)
 16. 安装 XrayR 官方版 (v0.9.4，已停止维护)
 17. 安装 XrayR 后端对接 (柚子备份版，需配置)
 18. 安装 v2node 后端对接 (官方版)
--------------------------------------------------
 19. 卸载并删除本脚本
 0. 退出脚本 (或双击回车)
==================================================
```

## 公网 IPv4 默认出口

菜单 `6` 用于检测网卡绑定的公网 IPv4、当前首选源 IP 和外部实际出口。

- 临时设置默认出口
- 设置默认出口并永久生效
- 取消永久设置

仅支持当前默认网卡上的 IPv4。切换前后会验证公网出口，失败时自动恢复。
