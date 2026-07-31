# Ubuntu 远程桌面配置与 WSL xrdp 黑屏修复笔记

> 日期：2026-07-31
> 标签：`Ubuntu` `xrdp` `XFCE` `WSL` `远程桌面` `黑屏修复`
> 类型：主题笔记（环境配置 + 排错）

---

## 一、Ubuntu 上启动桌面（XFCE + xrdp）

依次执行以下命令安装并启动远程桌面：

```bash
sudo apt update
sudo apt install xfce4 xfce4-goodies xrdp -y
echo "startxfce4" > ~/.xsession
sudo systemctl enable xrdp
sudo systemctl start xrdp
hostname -I
```

要点说明：

- `xfce4` + `xfce4-goodies`：轻量桌面环境，比 GNOME 更适合远程/容器场景
- `~/.xsession` 写入 `startxfce4`：告诉会话管理器登录后启动 XFCE
- `systemctl enable/start xrdp`：开机自启并立即启动服务
- `hostname -I`：查看本机 IP，RDP 客户端用这个 IP 连接（默认端口 3389）

---

## 二、WSL 下连接黑屏的问题

### 问题现象

在 WSL 中按上面步骤配置后，用 RDP 客户端连接，结果是**黑屏 + 鼠标指针**，桌面不显示。

### 问题根源

**WSL 版本与 xrdp 冲突**：WSL 的某些新版本（特别是 **2.5.7 及之后的 2.6.x 系列**）与 xrdp 存在兼容性问题，会导致连接后只有黑屏和鼠标指针。

> **根因总结**：本质是 **xrdp 的启动脚本（`/etc/xrdp/startwm.sh`）没有正确指向 XFCE 桌面环境**，加上 WSL 新版对某些环境变量（DBUS / XDG）的处理变化，导致 XFCE 会话没被正确拉起。

---

## 三、解决方案（按推荐顺序）

### 方案一：降级 WSL 版本（最直接有效）

如果问题由新版 WSL 引起，降级到旧版最直接。

- 从微软官方 GitHub 仓库下载 **WSL 2.4.13** 安装包：`wsl.2.4.13.0.x64.msi`
  - 已知 **2.4.13** 是稳定版本；从 **2.5.7** 开始出现与 xrdp 的兼容问题
- 运行 `.msi` 安装包，会自动卸载当前新版并安装旧版，**不影响已有的 Linux 发行版和数据**
- 安装完成后**重启 Windows**
- 重启后重新远程连接，问题通常解决

### 方案二：修改 xrdp 启动脚本（配置修复，核心方法）

这是最核心的修复——确保 xrdp 能正确启动 XFCE。

1. 编辑启动脚本：

```bash
sudo nano /etc/xrdp/startwm.sh
```

2. 找到文件末尾的 `test` 和 `exec` 相关行，全部注释掉（行首加 `#`），然后在文件**最末尾**添加：

```bash
# 注释掉原来的几行
#test -x /etc/X11/Xsession && exec /etc/X11/Xsession
#exec /bin/sh /etc/X11/Xsession

# 添加以下两行
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
startxfce4
```

> `unset` 这两行是为了清除 WSL 新版中可能冲突的环境变量，避免它们干扰 XFCE 会话启动。

3. 保存退出（`Ctrl+O` → 回车 → `Ctrl+X`），重启 xrdp：

```bash
sudo systemctl restart xrdp
```

---

## 四、核心要点速记

| 主题 | 一句话 |
|------|--------|
| 桌面选择 | XFCE 轻量，适合远程/容器；`~/.xsession` 指定 `startxfce4` |
| 黑屏根因 | WSL 2.5.7+/2.6.x 与 xrdp 冲突 + startwm.sh 没指向 XFCE |
| 方案一 | 降级 WSL 到 2.4.13（最省心，不影响数据） |
| 方案二 | 改 `/etc/xrdp/startwm.sh`：注释原 exec 行，加 `unset DBUS/XDG` + `startxfce4`，再 `restart xrdp` |
| 关键变量 | `DBUS_SESSION_BUS_ADDRESS` 和 `XDG_RUNTIME_DIR` 在新版 WSL 下易冲突，需 unset |

---

> 适用场景：Ubuntu / WSL2 + xrdp 远程桌面黑屏排查。优先试方案二（零风险改配置），不行再考虑方案一（降级 WSL）。
