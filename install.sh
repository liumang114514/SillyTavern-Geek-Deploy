#!/bin/bash
# ==============================================================================
# SillyTavern 云端终极部署脚本 (Caddy 代理 / 16位安全后缀 / 随机端口版)
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行此脚本 (sudo bash install.sh)${NC}"
    exit 1
fi

INSTALL_DIR="/opt/SillyTavern"
CLI_PATH="/usr/local/bin/silly"

# 清理冲突端口 (释放 80/443)
echo -e "${BLUE}[1/6] 检查并清理冲突的 Web 服务 (如 Nginx/Apache)...${NC}"
systemctl stop nginx apache2 2>/dev/null
systemctl disable nginx apache2 2>/dev/null

echo -e "${BLUE}[2/6] 检查并安装 Node.js 环境...${NC}"
apt update -y >/dev/null 2>&1
apt install -y curl git build-essential jq >/dev/null 2>&1

ST_NODE_VER=$(curl -s https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json | grep -o '"node": *">=[0-9]*' | grep -o '[0-9]*' | head -n 1)
if [[ -z "$ST_NODE_VER" ]]; then
    ST_NODE_VER="20"
fi

if ! command -v node >/dev/null 2>&1 || [[ $(node -v) != v${ST_NODE_VER}* ]]; then
    echo -e "正在安装 Node.js v${ST_NODE_VER} LTS..."
    curl -fsSL https://deb.nodesource.com/setup_${ST_NODE_VER}.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
else
    echo -e "Node.js v${ST_NODE_VER} 环境已满足"
fi

echo -e "${BLUE}[3/6] 正在安装 Caddy 网关 (用于处理 HTTPS 和 16位安全后缀)...${NC}"
apt install -y debian-keyring debian-archive-keyring apt-transport-https >/dev/null 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null 2>&1
apt update >/dev/null 2>&1
apt install -y caddy >/dev/null 2>&1

echo -e "${BLUE}[4/6] 正在部署 SillyTavern 极简版源码...${NC}"
rm -rf $INSTALL_DIR
git clone -b release https://github.com/SillyTavern/SillyTavern.git $INSTALL_DIR >/dev/null 2>&1
cd $INSTALL_DIR
npm install --omit=dev >/dev/null 2>&1
echo "release" > $INSTALL_DIR/.branch

echo -e "${BLUE}[5/6] 正在配置安全防护 (随机端口与动态暗号)...${NC}"
IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
IP_HYPHEN=$(echo "$IP" | tr '.' '-')
DOMAIN="${IP_HYPHEN}.nip.io"
PORT=$(shuf -i 10000-60000 -n 1)
SECRET_SUFFIX=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
USER="silly"
PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)

echo "$PORT" > $INSTALL_DIR/.port
echo "$SECRET_SUFFIX" > $INSTALL_DIR/.suffix
echo "$DOMAIN" > $INSTALL_DIR/.domain
echo "$USER" > $INSTALL_DIR/.user
echo "$PASS" > $INSTALL_DIR/.pass

cat > $INSTALL_DIR/Caddyfile << EOF
${DOMAIN}:${PORT} {
    @knock path /${SECRET_SUFFIX}
    handle @knock {
        header Set-Cookie "st_auth=${SECRET_SUFFIX}; Path=/; HttpOnly; Max-Age=86400"
        redir * /
    }
    @auth {
        header_regexp Cookie st_auth=${SECRET_SUFFIX}
    }
    handle @auth {
        basicauth * {
            ${USER} $(/usr/local/bin/caddy hash-password --plaintext "${PASS}")
        }
        reverse_proxy 127.0.0.1:8000
    }
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
Restart=always
RestartSec=3

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
    echo -e "  [6] \033[0;32m🟩  更新 Node.js 运行环境 (至官方最新LTS)\033[0m"
    echo -e "  [7] \033[0;36m⏹️  停止 / 启动 服务\033[0m"
    echo -e "  [8] \033[0;31m🗑️  卸载 SillyTavern 与代理\033[0m"
    echo -e "  [9] \033[0;34m🛡️  升级 Caddy 网关防线到最新版\033[0m"
    echo -e "  [10] \033[0;35m📝  查看酒馆运行日志\033[0m"
    echo -e "  [0] \033[0;37m🚪  退出\033[0m"
    echo -e "\033[0;34m======================================================\033[0m"
    read -p "请输入选择 [0-10]: " choice
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
            systemctl restart sillytavern caddy
            echo -e "服务已重启。"
            read -p "按回车键返回..."
            ;;
        3)
            read -p "请输入新账号: " new_user
            read -p "请输入新密码: " new_pass
            if [[ -n "$new_user" && -n "$new_pass" ]]; then
                echo "$new_user" > $INSTALL_DIR/.user
                echo "$new_pass" > $INSTALL_DIR/.pass
                PORT=$(cat $INSTALL_DIR/.port)
                DOMAIN=$(cat $INSTALL_DIR/.domain)
                SUFFIX=$(cat $INSTALL_DIR/.suffix)
                cat > $INSTALL_DIR/Caddyfile << EOF2
${DOMAIN}:${PORT} {
    @knock path /${SUFFIX}
    handle @knock {
        header Set-Cookie "st_auth=${SUFFIX}; Path=/; HttpOnly; Max-Age=86400"
        redir * /
    }
    @auth {
        header_regexp Cookie st_auth=${SUFFIX}
    }
    handle @auth {
        basicauth * {
            ${new_user} $(/usr/local/bin/caddy hash-password --plaintext "${new_pass}")
        }
        reverse_proxy 127.0.0.1:8000
    }
    handle {
        abort
    }
}
EOF2
                systemctl restart caddy
                echo -e "账号密码已修改并生效！"
            else
                echo -e "账号或密码不能为空！"
            fi
            read -p "按回车键返回..."
            ;;
        4)
            PORT=$(cat $INSTALL_DIR/.port)
            DOMAIN=$(cat $INSTALL_DIR/.domain)
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
            BRANCH=$(cat $INSTALL_DIR/.branch 2>/dev/null || echo "release")
            git fetch --all
            git checkout $BRANCH
            git pull origin $BRANCH
            npm install --omit=dev
            systemctl restart sillytavern
            echo -e "更新完成！"
            read -p "按回车键返回..."
            ;;
        6)
            echo -e "正在检测官方最新要求的 Node.js 版本..."
            ST_NODE_VER=$(curl -s https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json | grep -o '"node": *">=[0-9]*' | grep -o '[0-9]*' | head -n 1)
            if [[ -z "$ST_NODE_VER" ]]; then
                ST_NODE_VER="20"
            fi
            echo -e "官方要求的最低 Node 大版本为: v${ST_NODE_VER}"
            echo -e "正在为您升级到该版本的最新 LTS..."
            curl -fsSL https://deb.nodesource.com/setup_${ST_NODE_VER}.x | bash - >/dev/null 2>&1
            apt-get install -y nodejs >/dev/null 2>&1
            echo -e "Node.js 环境升级完成！当前版本: $(node -v)"
            systemctl restart sillytavern
            read -p "按回车键返回..."
            ;;
        7)
            if [ "$(systemctl is-active sillytavern)" == "active" ]; then
                systemctl stop sillytavern caddy
                echo "已停止"
            else
                systemctl start sillytavern caddy
                echo "已启动"
            fi
            read -p "按回车键返回..."
            ;;
        8)
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
        9)
            echo -e "正在在线拉取 Caddy 最新版内核并升级..."
            /usr/local/bin/caddy upgrade
            systemctl restart caddy
            echo -e "Caddy 防线已升级至最新版本！"
            read -p "按回车键返回..."
            ;;
        10)
            echo -e "正在打开酒馆后台日志..."
            echo -e "💡 提示：你可以按上下方向键翻页，按 \033[0;31m'q'\033[0m 键退出日志查看。"
            sleep 2
            journalctl -u sillytavern -f -n 50
            ;;
        0)
            exit 0
            ;;
        *)
            ;;
    esac
    show_menu
}
show_menu
EOF
chmod +x $CLI_PATH

echo -e "${GREEN}🎉 SillyTavern 部署成功！${NC}"
echo -e "正在启动控制台..."
sleep 2
$CLI_PATH
