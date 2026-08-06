# Debian 云服务器一键配置 (XFCE + RDP)

在 Debian 12/13 云服务器上自动完成：修复 APT 源 → 安装 XFCE 桌面 → 配置 xrdp 远程桌面。

## 快速使用

```bash
# 1. 下载脚本
wget https://raw.githubusercontent.com/aaawiki/dev-learning-notes/main/debian-cloud-setup/setup.sh

# 2. 赋予执行权限
chmod +x setup.sh

# 3. 以 root 运行
sudo ./setup.sh
```

## 做了什么

| 步骤 | 说明 |
|------|------|
| 修复 APT 源 | Debian 12+ 的 `.sources` 文件若 `Types: deb deb-src` 会导致主仓库被跳过 |
| 装 XFCE | `xfce4` + `xfce4-goodies` 全家桶 |
| 装 xrdp | 监听 3389 端口，Windows 自带远程桌面直接连 |
| 创建用户 | 交互式创建，默认用户名 `wzy`，自动加入 sudo 组 |

## 常见问题

### APT 找不到 xfce4 包
根因：`/etc/apt/sources.list.d/debian.sources` 中 `Types: deb deb-src` 里的 `deb-src` 导致主仓库被忽略。

修复：去掉 `deb-src`，只保留 `deb`。脚本会自动处理。

### SSH 被 VPN 拦截（Clash）
Clash TUN 模式会拦截 22 端口 SSH 流量。

修复：在 Clash Verge → Merge 配置的 `prepend-rules` 中加入：
```yaml
- DST-PORT,22,DIRECT
```

### RDP 连接后黑屏
确保用户目录有 `~/.xsession` 文件，内容为 `startxfce4`。脚本已自动创建。

## 测试环境

- Debian 13 (trixie) on AWS EC2 t3.small
- XFCE 4.20
- xrdp 0.10
