#!/bin/bash
# ==============================================================================
# SillyTavern 云端终极部署脚本 (Caddy 代理 / 16位安全后缀 / 随机端口版)
# 作者: Antigravity AI
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

INSTALL_DIR="/opt/SillyTavern"
CLI_PATH="/usr/local/bin/silly"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] 请使用 root 权限运行此脚本 (例如: sudo -i)${NC}"
    exit 1
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN}  欢迎使用 SillyTavern 极简云端部署脚本${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. 选择版本
echo -e "\n${YELLOW}请选择你要安装的 SillyTavern 版本：${NC}"
echo -e "  [1] 最新官方 Release 版 (推荐，包含最新功能)"
echo -e "  [2] 1.14.0 老版本 (针对需要特定旧版插件的用户)"
read -p "请输入数字 [1/2] (默认: 1): " VER_CHOICE
if [ "$VER_CHOICE" == "2" ]; then
    ST_BRANCH="1.14.0"
else
    ST_BRANCH="release"
fi

# 2. 自定义域名设置
echo -e "\n${YELLOW}是否绑定自定义域名？${NC}"
echo -e "注意：如果你输入了域名，请务必确保域名的 A 记录已指向本服务器！"
read -p "请输入域名 [直接回车则自动生成无域名的 IP 加密链接]: " CUSTOM_DOMAIN

echo -e "${YELLOW}正在智能检测服务器 IP (优先检测 IPv4)...${NC}"
# 强制优先获取 IPv4
PUBLIC_IP=$(curl -s -4 ifconfig.me 2>/dev/null)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s -4 api.ipify.org 2>/dev/null)
fi

IS_IPV6=false
if [ -z "$PUBLIC_IP" ]; then
    # 退避使用 IPv6
    PUBLIC_IP=$(curl -s -6 ifconfig.me 2>/dev/null)
    IS_IPV6=true
fi

if [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}[ERROR] 无法获取任何公网 IP (IPv4 和 IPv6 均失败)，请检查网络！${NC}"
    exit 1
fi

if [ -n "$CUSTOM_DOMAIN" ]; then
    DOMAIN="$CUSTOM_DOMAIN"
    echo -e "${GREEN}已设置为自定义域名: ${DOMAIN}${NC}"
else
    if [ "$IS_IPV6" = true ]; then
        DOMAIN="${PUBLIC_IP//:/-}.sslip.io"
        echo -e "${GREEN}检测到纯 IPv6 服务器，自动分配: ${DOMAIN}${NC}"
    else
        DOMAIN="${PUBLIC_IP//./-}.nip.io"
        echo -e "${GREEN}成功获取 IPv4 地址，自动分配泛域名: ${DOMAIN}${NC}"
    fi
fi

# 3. 随机端口与安全后缀生成
echo -e "\n${YELLOW}请设置酒馆对外运行端口：${NC}"
read -p "请输入端口号 [回车自动随机生成 10000-60000]: " PORT
if [ -z "$PORT" ]; then
    PORT=$(shuf -i 10000-60000 -n 1)
fi

# 自动生成 16 位安全后缀和 8 位账号密码
SECRET_SUFFIX=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
ST_USER=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
ST_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)

echo -e "\n${GREEN}---- 部署信息预览 ----${NC}"
echo -e "安装版本: ${ST_BRANCH}"
echo -e "绑定域名: ${DOMAIN}"
echo -e "运行端口: ${PORT}"
echo -e "安全后缀: ${SECRET_SUFFIX}"
echo -e "登录账号: ${ST_USER}"
echo -e "----------------------"
read -p "按回车键开始全自动安装..." 

# ----------------- 开始安装 -----------------
echo -e "\n${BLUE}[1/6] 正在停止冲突的 Web 服务并安装依赖...${NC}"
systemctl stop nginx apache2 caddy 2>/dev/null || true
systemctl disable nginx apache2 2>/dev/null || true

apt update -y >/dev/null 2>&1
apt install -y curl git build-essential jq >/dev/null 2>&1

if ! command -v node &> /dev/null || [[ $(node -v) != v20* ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
fi

echo -e "${BLUE}[2/6] 正在安装 Caddy 网关 (用于处理 HTTPS 和 16位安全后缀)...${NC}"
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    CADDY_ARCH="arm64"
else
    CADDY_ARCH="amd64"
fi
curl -sL "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}" -o /usr/local/bin/caddy
chmod +x /usr/local/bin/caddy

echo -e "${BLUE}[3/6] 正在从官方拉取源码并安装依赖 (${ST_BRANCH})...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi
git clone -b $ST_BRANCH https://github.com/SillyTavern/SillyTavern.git "$INSTALL_DIR" >/dev/null 2>&1
cd "$INSTALL_DIR" || exit
npm install --omit=dev >/dev/null 2>&1

# 保存环境元数据
echo "$DOMAIN" > $INSTALL_DIR/.domain
echo "$PORT" > $INSTALL_DIR/.port
echo "$SECRET_SUFFIX" > $INSTALL_DIR/.suffix
echo "$ST_USER" > $INSTALL_DIR/.user
echo "$ST_PASS" > $INSTALL_DIR/.pass

echo -e "${BLUE}[4/6] 正在配置后台参数...${NC}"
cp default/config.yaml config.yaml 2>/dev/null || cp default.yaml config.yaml 2>/dev/null
# 因为 Caddy 会负责外网访问，SillyTavern 本体安全地绑定在本地 8000 端口
sed -i "s/listen: 127.0.0.1/listen: 127.0.0.1/g" config.yaml
sed -i "s/port: 8000/port: 8000/g" config.yaml
sed -i "s/whitelistMode: true/whitelistMode: false/g" config.yaml
sed -i "s/basicAuthMode: true/basicAuthMode: false/g" config.yaml

# 生成密码哈希给 Caddy 使用
HASH=$(/usr/local/bin/caddy hash-password --plaintext "${ST_PASS}")

echo -e "${BLUE}[5/6] 正在配置防火墙和系统服务...${NC}"
cat > $INSTALL_DIR/Caddyfile << EOF
${DOMAIN}:${PORT} {
    @knock path /${SECRET_SUFFIX}
    handle @knock {
        header Set-Cookie "st_auth=${SECRET_SUFFIX}; Path=/; HttpOnly; Max-Age=86400"
        redir * /
    }

    # 2. 验证是否带有 Cookie
    @auth {
        header_regexp Cookie st_auth=${SECRET_SUFFIX}
    }

    handle @auth {
        basicauth * {
            ${ST_USER} ${HASH}
        }
        reverse_proxy 127.0.0.1:8000
    }

    # 3. 不符合条件的扫描器全部 404
    handle {
        abort
    }
}
EOF

cat > /etc/systemd/system/sillytavern.service << EOF
[Unit]
Description=SillyTavern Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/caddy.service << EOF
[Unit]
Description=Caddy Proxy
After=network.target

[Service]
Type=notify
User=root
ExecStart=/usr/local/bin/caddy run --environ --config $INSTALL_DIR/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config $INSTALL_DIR/Caddyfile --force
TimeoutStopSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sillytavern caddy >/dev/null 2>&1
systemctl restart sillytavern caddy

# 配置 Caddy 自动更新防范 0day 漏洞 (每天凌晨 4 点执行)
echo "0 4 * * * root /usr/local/bin/caddy upgrade && systemctl restart caddy >/dev/null 2>&1" > /etc/cron.d/caddy-upgrade
chmod 644 /etc/cron.d/caddy-upgrade

echo -e "${BLUE}[6/6] 正在生成 'silly' 终端控制台...${NC}"
cat > $CLI_PATH << 'EOF'
#!/bin/bash
INSTALL_DIR="/opt/SillyTavern"

show_menu() {
    clear
    echo -e "\033[0;34m======================================================\033[0m"
    echo -e "  \033[0;32m🍺 SillyTavern 管理控制台\033[0m (状态: $(systemctl is-active sillytavern))"
    echo -e "\033[0;34m======================================================\033[0m"
    echo -e "  [1] \033[0;36m👁️  查看酒馆完整登录地址 (含后缀) 与账号密码\033[0m"
    echo -e "  [2] \033[0;36m🔄  重启所有服务 (SillyTavern + Caddy)\033[0m"
    echo -e "  [3] \033[0;33m🔑  修改/重置账号与密码\033[0m"
    echo -e "  [4] \033[0;35m🛠️  重新生成 16位安全后缀\033[0m"
    echo -e "  [5] \033[0;32m⬆️  从官方源码拉取最新更新 (SillyTavern)\033[0m"
    echo -e "  [6] \033[0;36m⏹️  停止 / 启动 服务\033[0m"
    echo -e "  [7] \033[0;31m🗑️  卸载 SillyTavern 与代理\033[0m"
    echo -e "  [8] \033[0;34m🛡️  升级 Caddy 网关防线到最新版\033[0m"
    echo -e "  [9] \033[0;35m📝  查看酒馆运行日志\033[0m"
    echo -e "  [0] \033[0;37m🚪  退出\033[0m"
    echo -e "\033[0;34m======================================================\033[0m"
    read -p "请输入选择 [0-9]: " choice
    case $choice in
        1)
            PORT=$(cat $INSTALL_DIR/.port)
            SUFFIX=$(cat $INSTALL_DIR/.suffix)
            DOMAIN=$(cat $INSTALL_DIR/.domain 2>/dev/null)
            USER=$(cat $INSTALL_DIR/.user 2>/dev/null)
            PASS=$(cat $INSTALL_DIR/.pass 2>/dev/null)
            
            echo -e "\n\033[0;31m⚠️ 必须通过带有后缀的完整地址进行第一次访问，否则会报404！\033[0m"
            echo -e "\033[0;32m🌐 完整访问地址:\033[0m https://${DOMAIN}:${PORT}/${SUFFIX}"
            echo -e "\033[0;32m👤 登录账号:\033[0m ${USER}"
            echo -e "\033[0;32m🔑 登录密码:\033[0m ${PASS}"
            read -p "按回车键返回..."
            ;;
        2)
            echo -e "正在重启..."
            systemctl restart sillytavern caddy
            echo -e "重启完成！"
            read -p "按回车键返回..."
            ;;
        3)
            echo -e "\n当前账号密码如下："
            grep "basicAuth" $INSTALL_DIR/config.yaml
            read -p "输入新账号 (回车随机生成): " NEW_USER
            read -p "输入新密码 (回车随机生成): " NEW_PASS
            [ -z "$NEW_USER" ] && NEW_USER=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
            [ -z "$NEW_PASS" ] && NEW_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
            echo "$NEW_USER" > $INSTALL_DIR/.user
            echo "$NEW_PASS" > $INSTALL_DIR/.pass
            
            # 更新 Caddyfile 里的哈希和账号
            NEW_HASH=$(/usr/local/bin/caddy hash-password --plaintext "${NEW_PASS}")
            sed -i -E "s/basicauth \* \{.*\}/basicauth \* \{\n            ${NEW_USER} ${NEW_HASH}\n        \}/" $INSTALL_DIR/Caddyfile
            systemctl restart caddy
            echo -e "账号已修改为: ${NEW_USER}"
            echo -e "密码已修改为: ${NEW_PASS}"
            read -p "按回车键返回..."
            ;;
        4)
            DOMAIN=$(cat $INSTALL_DIR/.domain)
            PORT=$(cat $INSTALL_DIR/.port)
            NEW_SUFFIX=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
            echo "$NEW_SUFFIX" > $INSTALL_DIR/.suffix
            
            cat > $INSTALL_DIR/Caddyfile << EOF2
${DOMAIN}:${PORT} {
    @knock path /${NEW_SUFFIX}
    handle @knock {
        header Set-Cookie "st_auth=${NEW_SUFFIX}; Path=/; HttpOnly; Max-Age=86400"
        redir * /
    }
    @auth {
        header_regexp Cookie st_auth=${NEW_SUFFIX}
    }
    handle @auth {
        basicauth * {
            $(cat $INSTALL_DIR/.user) $(/usr/local/bin/caddy hash-password --plaintext "$(cat $INSTALL_DIR/.pass)")
        }
        reverse_proxy 127.0.0.1:8000
    }
    handle {
        abort
    }
}
EOF2
            systemctl restart caddy
            echo -e "新的安全后缀已生效！请查看选项 1 获取新地址。"
            read -p "按回车键返回..."
            ;;
        5)
            echo -e "正在从官方仓库拉取更新..."
            cd $INSTALL_DIR
            git pull
            npm install --omit=dev
            systemctl restart sillytavern
            echo -e "更新完成！"
            read -p "按回车键返回..."
            ;;
        6)
            if [ "$(systemctl is-active sillytavern)" == "active" ]; then
                systemctl stop sillytavern caddy
                echo "已停止"
            else
                systemctl start sillytavern caddy
                echo "已启动"
            fi
            read -p "按回车键返回..."
            ;;
        7)
            read -p "确认卸载吗？所有数据将会丢失！[y/N]: " del_confirm
            if [[ "$del_confirm" == "y" || "$del_confirm" == "Y" ]]; then
                systemctl stop sillytavern caddy
                systemctl disable sillytavern caddy
                rm -rf $INSTALL_DIR
                rm /etc/systemd/system/sillytavern.service
                rm /etc/systemd/system/caddy.service
                rm -f /etc/cron.d/caddy-upgrade
                systemctl daemon-reload
                rm -f /usr/local/bin/silly
                rm -f /usr/local/bin/caddy
                echo -e "SillyTavern 与网关代理已完全卸载。"
                exit 0
            fi
            ;;
        8)
            echo -e "正在在线拉取 Caddy 最新版内核并升级..."
            /usr/local/bin/caddy upgrade
            systemctl restart caddy
            echo -e "Caddy 防线已升级至最新版本！"
            read -p "按回车键返回..."
            ;;
        9)
            echo -e "正在打开酒馆后台日志..."
            echo -e "💡 提示：你可以按上下方向键翻页，按 \033[0;31m'q'\033[0m 键退出日志查看。"
            sleep 2
            journalctl -u sillytavern -n 200
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效输入"
            sleep 1
            ;;
    esac
}

while true; do
    show_menu
done
EOF

chmod +x $CLI_PATH

clear
echo -e "=================================================================="
echo -e "${GREEN}🎉 SillyTavern 部署成功！${NC}"
echo -e "=================================================================="
echo -e "⚠️ 注意: 必须通过以下【带有后缀的完整链接】进行第一次访问！"
echo -e "如果直接输入域名或 IP，服务器将强制返回 404 错误！"
echo -e "------------------------------------------------------------------"
echo -e "🌐 安全专属敲门砖地址: ${YELLOW}https://${DOMAIN}:${PORT}/${SECRET_SUFFIX}${NC}"
echo -e "👤 登录账号:           ${GREEN}${ST_USER}${NC}"
echo -e "🔑 登录密码:           ${GREEN}${ST_PASS}${NC}"
echo -e "=================================================================="
echo -e "💡 日后随时在终端输入 ${YELLOW}silly${NC} 即可呼出管理面板！"
echo -e "⚠️ 请务必去你的云服务商后台(如阿里云)放行 80 端口和 ${PORT} 端口！"
echo -e "=================================================================="
