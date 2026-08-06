#!/bin/bash
# ============================================================
# Debian 云服务器一键配置脚本
# 适用于: Debian 12/13 (bookworm/trixie) AWS EC2 等云环境
# 功能:   修复 apt 源 → 装 XFCE 桌面 → 配 xrdp 远程桌面
# 用法:   chmod +x setup.sh && sudo ./setup.sh
# ============================================================
set -e

echo "=========================================="
echo " Debian 云服务器 XFCE + RDP 一键配置"
echo "=========================================="

# ---- 1. 修复 APT 源 ----
# Debian 12+ 使用 DEB822 格式(.sources)，若 Types 含 deb-src
# 可能导致主仓库被跳过，仅保留 security 仓库。
echo ""
echo "[1/4] 检查并修复 APT 源..."

SOURCE_FILE="/etc/apt/sources.list.d/debian.sources"
if [ -f "$SOURCE_FILE" ]; then
    # 移除 Types 中的 deb-src，避免主仓库被跳过
    sed -i 's/Types: deb deb-src/Types: deb/g' "$SOURCE_FILE"
    echo "  ✓ 已修复 $SOURCE_FILE (移除 deb-src)"
else
    # 不存在则创建传统 sources.list
    cat > /etc/apt/sources.list <<'SOURCEEOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
SOURCEEOF
    echo "  ✓ 已创建 /etc/apt/sources.list (传统格式)"
fi

apt-get update -qq
echo "  ✓ APT 源更新完成 ($(apt list 2>/dev/null | wc -l) 个包可用)"

# ---- 2. 安装 XFCE 桌面 ----
echo ""
echo "[2/4] 安装 XFCE 桌面环境 (可能需要几分钟)..."
apt-get install -y -qq xfce4 xfce4-goodies
echo "  ✓ XFCE 4.x 安装完成"

# ---- 3. 安装 xrdp (远程桌面) ----
echo ""
echo "[3/4] 安装 xrdp 远程桌面..."
apt-get install -y -qq xrdp xorgxrdp
systemctl enable --now xrdp

# 配置 xrdp 使用 XFCE 会话
echo "startxfce4" > /etc/skel/.xsession
for home in /home/*; do
    [ -d "$home" ] && echo "startxfce4" > "$home/.xsession"
done
echo "  ✓ xrdp 已启动，监听 3389 端口"

# ---- 4. 创建新用户 (可选) ----
echo ""
echo "[4/4] 用户设置"
DEFAULT_USER="wzy"
read -p "  创建新用户? (默认: $DEFAULT_USER, 按回车确认或输入用户名): " NEW_USER
NEW_USER="${NEW_USER:-$DEFAULT_USER}"

if ! id "$NEW_USER" &>/dev/null; then
    echo -n "  请输入 ${NEW_USER} 的密码: "
    read -s USER_PASS
    echo ""
    useradd -m -s /bin/bash "$NEW_USER"
    echo "${NEW_USER}:${USER_PASS}" | chpasswd
    usermod -aG sudo "$NEW_USER"
    echo "startxfce4" > "/home/${NEW_USER}/.xsession"
    chown "${NEW_USER}:${NEW_USER}" "/home/${NEW_USER}/.xsession"
    echo "  ✓ 用户 $NEW_USER 已创建并加入 sudo 组"
else
    echo "  ⚠ 用户 $NEW_USER 已存在，跳过创建"
fi

# ---- 完成 ----
echo ""
echo "=========================================="
echo " 配置完成！"
echo "=========================================="
echo ""
echo " RDP 连接信息:"
echo "   地址: $(curl -s ifconfig.me 2>/dev/null || echo '<服务器IP>'):3389"
echo "   用户: $NEW_USER"
echo ""
echo " Windows 连接: Win+R → mstsc → 输入地址"
echo "=========================================="
