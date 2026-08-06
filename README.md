# SillyTavern 一键部署脚本

适用于 Linux (Ubuntu/Debian) VPS 的 SillyTavern（酒馆）自动化部署与反向代理脚本。

## 🌟 特性

- **一键自动化**：自动安装 Node.js (LTS)、SillyTavern 及 Caddy 反向代理。
- **自动 SSL 证书**：支持自定义域名，或自动生成魔法域名（`nip.io` IPv4 / `sslip.io` IPv6）并自动申请 Let's Encrypt HTTPS 证书。
- **原生安全锁定**：采用 SillyTavern 原生用户认证，自动加密锁定初始账户，防止未授权访问。
- **最小权限运行**：酒馆进程以低权限 `nobody` 用户身份运行，提高系统安全性。
- **快捷管理控制台**：部署完成后在终端输入 `silly` 即可呼出快捷菜单（支持查看地址与账户、重置密码、一键更新酒馆与代理组件、查看日志、彻底卸载）。

## 🚀 快速开始

在全新干净的 Linux VPS (如 Ubuntu 20.04+ / Debian 11+) 上，使用 `root` 权限运行以下命令：

```bash
bash <(curl -sL https://raw.githubusercontent.com/yewumian11432/SillyTavern-Geek-Deploy/main/install.sh)
```

## 🛠️ 控制台功能 (`silly`)

安装完成后，在终端随时输入 `silly` 即可进入管理面板：

```text
======================================================
               SillyTavern 快捷管理面板               
======================================================
  [1] 查看酒馆完整登录地址与初始账户
  [2] 重置酒馆登录密码
  [3] 重启所有服务 (SillyTavern + Caddy)
  [4] 查看酒馆运行日志
  [5] 一键更新酒馆与代理组件 (保留数据)
  [6] 彻底卸载酒馆与代理服务
  [0] 退出
======================================================
```

## 📜 许可证

[MIT](LICENSE)
