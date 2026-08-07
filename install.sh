#!/bin/bash
# ==============================================================================
# SillyTavern + Caddy 一键部署脚本 (纯净反代 + 原生锁定)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit
fi

echo "=========================================="
echo "开始部署 SillyTavern..."
echo "=========================================="
echo ""

# 1. 获取用户输入
read -p "请输入您的完整域名 [直接回车则使用魔法域名]: " CUSTOM_DOMAIN

if [ -n "$CUSTOM_DOMAIN" ]; then
    DOMAIN="$CUSTOM_DOMAIN"
else
    echo "请选择魔法域名类型："
    echo "  [1] IPv4 (自动分配 .nip.io 后缀)"
    echo "  [2] IPv6 (自动分配 .sslip.io 后缀)"
    read -p "请输入选项 [1 或 2，默认优先 1]: " IP_CHOICE
    
    if [ "$IP_CHOICE" = "2" ]; then
        PUBLIC_IP=$(curl -s -6 ifconfig.me 2>/dev/null)
        if [ -z "$PUBLIC_IP" ]; then
            echo "错误：无法获取公网 IPv6 地址，请确认服务器是否支持 IPv6！"
            exit 1
        fi
        DOMAIN="${PUBLIC_IP//:/-}.sslip.io"
    else
        PUBLIC_IP=$(curl -s -4 ifconfig.me 2>/dev/null)
        if [ -z "$PUBLIC_IP" ]; then
            PUBLIC_IP=$(curl -s -4 api.ipify.org 2>/dev/null)
        fi
        if [ -z "$PUBLIC_IP" ]; then
            echo "错误：无法获取公网 IPv4 地址！"
            exit 1
        fi
        DOMAIN="${PUBLIC_IP//./-}.nip.io"
    fi
fi
echo "使用域名: $DOMAIN"

read -p "请输入访问端口号 [直接回车则随机生成 10000-60000]: " PORT
if [ -z "$PORT" ]; then
    PORT=$(shuf -i 10000-60000 -n 1)
fi

echo "准备安装依赖..."
apt-get update
apt-get install -y curl git jq

curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# 2. 部署 SillyTavern
echo "正在下载 SillyTavern..."
rm -rf /opt/SillyTavern
git clone https://github.com/SillyTavern/SillyTavern.git /opt/SillyTavern
cd /opt/SillyTavern
npm install

echo "正在配置基本参数..."
cp default/config.yaml config.yaml 2>/dev/null || cp default.yaml config.yaml 2>/dev/null

# 彻底修复配置替换逻辑，确保正确关闭白名单并开启账号
node -e "
const fs = require('fs');
let conf = fs.readFileSync('config.yaml', 'utf8');
conf = conf.replace(/listen:\s*false/, 'listen: true');
conf = conf.replace(/ipv4:\s*0\.0\.0\.0/, 'ipv4: 127.0.0.1');
conf = conf.replace(/whitelistMode:\s*true/g, 'whitelistMode: false');
conf = conf.replace(/basicAuthMode:\s*true/, 'basicAuthMode: false');
conf = conf.replace(/enableUserAccounts:\s*false/, 'enableUserAccounts: true');
conf = conf.replace(/whitelist:[\s\S]*?whitelistDockerHosts:/, 'whitelist: []\nwhitelistDockerHosts:');
fs.writeFileSync('config.yaml', conf);
"

# 3. 生成原生密码并锁定 default-user
echo "正在生成初始安全密码..."
NODE_SCRIPT=$(cat << 'EOF'
const crypto = require('crypto');
const fs = require('fs');

const password = crypto.randomBytes(12).toString('base64url').slice(0, 16);
const salt = crypto.randomBytes(16).toString('base64');
const hash = crypto.scryptSync(password.normalize(), salt, 64).toString('base64');

const data = {
    key: "user:default-user",
    value: {
        handle: "default-user",
        name: "User",
        created: Date.now(),
        password: hash,
        admin: true,
        enabled: true,
        salt: salt
    }
};

const storageDir = '/opt/SillyTavern/data/_storage';
const storageFile = storageDir + '/' + crypto.createHash('sha256').update('user:default-user').digest('hex');

if (!fs.existsSync(storageDir)){
    fs.mkdirSync(storageDir, { recursive: true });
}

fs.writeFileSync(storageFile, JSON.stringify(data));
console.log(password);
EOF
)

ST_PASSWORD=$(node -e "$NODE_SCRIPT")

# 更改目录属主为 nobody，提升安全性
chown -R nobody:nogroup /opt/SillyTavern

# 保存环境元数据给控制台使用
echo "$DOMAIN" > /opt/SillyTavern/.domain
echo "$PORT" > /opt/SillyTavern/.port

# 4. 配置 Systemd
cat > /etc/systemd/system/sillytavern.service << EOF
[Unit]
Description=SillyTavern
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
WorkingDirectory=/opt/SillyTavern
ExecStart=/usr/bin/node server.js
Restart=always
Nice=-5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sillytavern

# 5. 安装与配置 Caddy
echo "正在配置 Caddy 反向代理..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install caddy -y

# 生成 Caddyfile
cat > /opt/SillyTavern/Caddyfile << EOF
$DOMAIN:$PORT {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8000
}
EOF

caddy stop 2>/dev/null || true
cp /opt/SillyTavern/Caddyfile /etc/caddy/Caddyfile
systemctl enable caddy
systemctl restart caddy

# 6. 生成傻瓜式控制台工具 (silly)
cat > /usr/local/bin/silly << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/opt/SillyTavern"

show_menu() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "               ${GREEN}SillyTavern 快捷管理面板${NC}               "
    echo -e "${BLUE}======================================================${NC}"
    echo -e "  [1] \033[0;36m查看酒馆完整登录地址与初始账户\033[0m"
    echo -e "  [2] \033[0;33m重置酒馆登录密码\033[0m"
    echo -e "  [3] \033[0;36m重启所有服务 (SillyTavern + Caddy)\033[0m"
    echo -e "  [4] \033[0;35m查看酒馆运行日志\033[0m"
    echo -e "  [5] \033[0;32m一键更新酒馆与代理组件 (保留数据)\033[0m"
    echo -e "  [6] \033[0;31m彻底卸载酒馆与代理服务\033[0m"
    echo -e "  [0] \033[0;37m退出\033[0m"
    echo -e "${BLUE}======================================================${NC}"
    read -p "请输入选择 [0-6]: " choice
    case $choice in
        1)
            DOMAIN=$(cat $INSTALL_DIR/.domain 2>/dev/null)
            PORT=$(cat $INSTALL_DIR/.port 2>/dev/null)
            
            echo -e "\n\033[0;32m🌐 完整访问地址:\033[0m https://${DOMAIN}:${PORT}"
            echo -e "\033[0;32m👤 初始登录账户:\033[0m default-user"
            echo -e "\033[0;33m(为了安全，控制台不再提供密码查看功能，遗忘请按 [2] 重置)\033[0m"
            read -p "按回车键返回..."
            ;;
        2)
            echo -e "\n"
            read -p "请输入新密码 (直接回车则随机生成 16 位高强度密码): " NEW_PASS
            if [ -z "$NEW_PASS" ]; then
                NEW_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
            fi
            
            echo "正在重置底层数据库密码..."
            NODE_SCRIPT=$(cat << 'EOF2'
const crypto = require('crypto');
const fs = require('fs');
const newPass = process.argv[1];
const salt = crypto.randomBytes(16).toString('base64');
const hash = crypto.scryptSync(newPass.normalize(), salt, 64).toString('base64');

const data = {
    key: "user:default-user",
    value: {
        handle: "default-user",
        name: "User",
        created: Date.now(),
        password: hash,
        admin: true,
        enabled: true,
        salt: salt
    }
};

const storageFile = '/opt/SillyTavern/data/_storage/' + crypto.createHash('sha256').update('user:default-user').digest('hex');
fs.writeFileSync(storageFile, JSON.stringify(data));
EOF2
)
            node -e "$NODE_SCRIPT" "$NEW_PASS"
            chown -R nobody:nogroup /opt/SillyTavern/data/_storage 2>/dev/null
            systemctl restart sillytavern
            echo -e "✅ 密码已成功重置为: \033[0;32m$NEW_PASS\033[0m"
            read -p "按回车键返回..."
            ;;
        3)
            echo -e "正在重启..."
            systemctl restart sillytavern caddy
            echo -e "重启完成！"
            read -p "按回车键返回..."
            ;;
        4)
            echo -e "正在打开酒馆后台日志..."
            echo -e "💡 提示：按 \033[0;31m'q'\033[0m 键退出日志查看。"
            sleep 2
            journalctl -u sillytavern -n 200
            ;;
        5)
            echo -e "正在拉取最新代码并更新依赖..."
            cd $INSTALL_DIR
            git pull
            npm install
            chown -R nobody:nogroup $INSTALL_DIR
            
            echo -e "正在检查并更新 Caddy 代理组件..."
            apt-get update >/dev/null 2>&1
            apt-get install --only-upgrade caddy -y >/dev/null 2>&1
            
            systemctl restart sillytavern caddy
            echo -e "✅ 更新完成！酒馆与代理服务已自动重启。"
            read -p "按回车键返回..."
            ;;
        6)
            echo -e "\n\033[0;31m警告：这将永久删除 SillyTavern 及其所有配置、本地数据，并卸载相关服务！\033[0m"
            read -p "你确定要继续吗？(y/N): " CONFIRM
            if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
                echo -e "正在卸载并清理环境..."
                systemctl stop sillytavern caddy 2>/dev/null
                systemctl disable sillytavern caddy 2>/dev/null
                rm -rf $INSTALL_DIR
                rm -f /etc/systemd/system/sillytavern.service
                rm -f /etc/caddy/Caddyfile
                systemctl daemon-reload
                echo -e "✅ 卸载完毕！所有残留已被清理。"
                rm -f /usr/local/bin/silly
                exit 0
            else
                echo -e "已取消卸载操作。"
                read -p "按回车键返回..."
            fi
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
chmod +x /usr/local/bin/silly

echo ""
echo "=========================================="
echo "SillyTavern 部署成功"
echo "=========================================="
echo "访问地址: https://$DOMAIN:$PORT"
echo ""
echo "初始登录账号: default-user"
echo "初始随机密码: $ST_PASSWORD"
echo ""
echo "提示：以后随时可以在命令行输入 silly 呼出控制台面板！"
echo "=========================================="
