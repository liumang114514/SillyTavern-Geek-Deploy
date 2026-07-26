# 🍺 SillyTavern 极简云端安全部署脚本

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)]()
[![Caddy](https://img.shields.io/badge/Proxy-Caddy-blue.svg)]()

> 这是目前全网**最安全、最极客、最省心**的 SillyTavern（酒馆）VPS 一键部署方案。
> 不仅实现了全自动部署，还融入了**黑洞丢弃**与**动态敲门**等军工级防御机制，让你的私人酒馆在公网上做到真正的“完全隐身”。

---

## 🌟 核心特性 (Features)

- 🔒 **全自动 HTTPS (Caddy 驱动)**：抛弃臃肿老旧的 Nginx。脚本自动利用 `nip.io`/`sslip.io` 魔法泛解析，**无需购买域名**也能白嫖 Let's Encrypt 正规绿锁，彻底告别浏览器不安全警告。
- 🕳️ **极致的“黑洞防扫” (Abort 丢弃模式)**：Caddy 在网关层直接拦截一切非法流量。不知道暗号的扫描器和爬虫，连 `404 Not Found` 都看不到，TCP 连接会被瞬间强行掐断（`abort`），服务器犹如处于关机状态，绝不泄漏任何服务指纹。
- 🔑 **24 小时动态敲门砖**：首创“Cookie 寿命控制法”。每次使用 16 位安全后缀访问后，会颁发一个 24 小时有效期的访问通行证。超时后自动剥夺访问权并跌入黑洞，设备遗失也无需担忧。
- 🛡️ **网关级强鉴权**：关闭酒馆自带的薄弱白名单，直接在最外层 Caddy 挂载原生 HTTP BasicAuth。密码哈希存储，就算黑客拿到 VPS 权限也无法逆向还原你的密码。
- 🤖 **全能 `silly` 终端控制台**：部署完成后，在任意终端输入 `silly` 即可呼出中文全功能控制台（支持：更新源码、重置暗号/密码、重启服务、**实时查看报错日志**等）。
- 🔄 **0day 漏洞自愈**：内置 Cron 定时任务，每天凌晨 4 点自动在线检测并无缝升级 Caddy 核心，防范各种 0day 安全漏洞。

---

## 🚀 快速开始 (Quick Start)

只需要一台拥有公网 IP 的干净 Linux VPS（推荐 Ubuntu 20.04+ / Debian 11+）。

### 1. 登录 VPS，执行一键安装：
```bash
bash <(curl -sL https://raw.githubusercontent.com/liumang114514/SillyTavern-Geek-Deploy/main/install.sh)
```
*(注：请将上面的链接替换为你自己 GitHub 仓库的 RAW 链接)*

### 2. 部署流程演示：
1. 脚本会智能检测你的 IPv4/IPv6。
2. 提示你选择想要的分支（Release 最新版 / 1.14.0 旧版）。
3. 全自动编译、下载依赖、配置 Caddy 网关及守护进程。
4. 安装完成后，终端会打印出包含 **16 位安全后缀** 的专属暗号链接与账号密码。

### 3. 日常维护
以后你只需在 VPS 终端输入：
```bash
silly
```
即可调出可视化控制台，轻松管理你的酒馆。

---

## 🛡️ 安全机制详解 (Security Architecture)

很多人直接把酒馆跑在公网 IP 上，这是极度危险的。本脚本采用了**双重锁屏+隐身披风**的架构：

1. **第一重：16位暗号路由**
   任何人访问你的网站，必须带上形如 `/Hdb6YLHzUOkRYfnB` 的暗号后缀。只要没带暗号，Caddy 会直接在底层强行断开 TCP 连接（不回复任何 HTTP 状态码），扫描器一无所获。
2. **第二重：Cookie 限定生命周期**
   访问正确的暗号后，Caddy 会给你的浏览器下发 `Max-Age=86400`（24小时）的身份 Cookie，然后重定向到首页。这就意味着：哪怕你浏览器保存了账号密码，只要超过 24 小时没有重新使用长链接“敲门”，依然会被踢入黑洞。
3. **第三重：网关密码**
   凭借 Cookie 走到门前，才会触发浏览器的原生密码弹窗进行最后一步验证。

---

## 🤝 鸣谢与声明
- 核心服务由 [SillyTavern](https://github.com/SillyTavern/SillyTavern) 官方项目提供。
- 网关路由采用 [Caddy Web Server](https://caddyserver.com/)。
- 本脚本由 `Gemini AI` 协助构建与极客优化，专为保护个人隐私而生。欢迎 Fork 和 Star！
