# Termux proot Debian 图形环境与硬件加速配置笔记（Turnip / VirGL）

> 标签：`Termux` `proot` `Debian` `termux-x11` `XFCE` `Turnip` `VirGL` `Zink` `Android` `硬件加速`
> 类型：主题笔记（环境搭建 + 排错）

---

## 一、核心环境概述

- **宿主机**：Android 平板，运行 Termux 应用
- **虚拟化方式**：`proot-distro` 创建 Debian 容器，**无需 root 权限**
- **显示服务**：`termux-x11`（显示器 `:1`，通过 X11 把画面输出到 Android 屏幕）
- **桌面环境**：XFCE4（轻量，适合 proot 环境）
- **目标**：利用高通 Adreno GPU（骁龙处理器）做 OpenGL 硬件加速

---

## 二、两种 GPU 加速方案对比

在 proot 容器里跑图形，OpenGL 应用本身不能直接碰 GPU，需要一层转换。常见三条路线：

| 方案 | 原理 | 性能 | 兼容性 | 适用硬件 |
|------|------|------|--------|----------|
| **VirGL** | Termux 端跑 `virgl_test_server_android` 后端，容器内用 `virpipe` 驱动 | 中等、稳定 | 几乎全设备 | 通用，无特殊要求 |
| **Turnip + Zink** | 容器内直接走 Vulkan（mesa-vulkan-kgsl 驱动）+ Zink 转 OpenGL，**无需 Termux 后端** | 优 | 有硬件要求 | 骁龙 + Adreno 600~700 系列 |
| **Zink（混合）** | Termux 端跑 Zink 后端，容器内调 `zink` 驱动 | 中等 | 较好 | 通用 |

**调用方式：**
```bash
# VirGL
GALLIUM_DRIVER=virpipe MESA_GL_VERSION_OVERRIDE=4.0 {程序}

# Turnip + Zink
MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform {程序}

# Zink（混合）
GALLIUM_DRIVER=zink MESA_GL_VERSION_OVERRIDE=4.0 {程序}
```

> **选型建议**：新手用 VirGL（稳）；设备支持（骁龙 6/7 系 + Adreno 600/700）且追求性能用 Turnip+Zink。

---

## 三、Turnip + Zink 实战配置

### 3.1 安装 Turnip 驱动包（Debian 12 容器）
```bash
# 适配：骁龙处理器 / Adreno 600~700 / Debian 12
sudo dpkg -i mesa-vulkan-kgsl_24.1.0-devel-20240120_arm64.deb
```
> Debian 13 可能缺 `libllvm15` / `libvulkan1`，需手动补装或强制安装（见第六节）。

### 3.2 最终可用的启动脚本（`sx11u`）
```bash
#!/data/data/com.termux/files/usr/bin/bash

# 唤醒锁，防止进程被系统杀死
termux-wake-lock

# 清理旧的 X11 进程
kill -9 $(pgrep -f "termux.x11") 2>/dev/null

# 启动 PulseAudio（网络音频支持）
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1

# 准备 termux-x11 会话（显示器 :1）
export XDG_RUNTIME_DIR=${TMPDIR}
termux-x11 :1 >/dev/null &
sleep 3

# 启动 Termux:X11 应用
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity > /dev/null 2>&1
sleep 1

# 登录 proot 容器，启动 XFCE 桌面（注入 Turnip 环境变量）
proot-distro login debian --shared-tmp -- /bin/bash -c  '
    export PULSE_SERVER=127.0.0.1
    export XDG_RUNTIME_DIR=${TMPDIR}
    su - <用户名> -c "env DISPLAY=:1 LANG=zh_CN.UTF-8 GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform startxfce4"
'

exit 0
```

### 3.3 关键环境变量说明
| 变量 | 值 | 作用 |
|------|-----|------|
| `MESA_LOADER_DRIVER_OVERRIDE` | `zink` | 强制 OpenGL 通过 Zink 层走 Vulkan 后端 |
| `TU_DEBUG` | `noconform` | Turnip 驱动调试标志，提升兼容性 |
| `DISPLAY` | `:1` | 指定 X11 显示服务器 |
| `PULSE_SERVER` | `127.0.0.1` | 指定本地音频服务器 |

---

## 四、Debian 软件源与版本选择

### 4.1 Debian 13 (Trixie) 源配置
传统格式 `/etc/apt/sources.list`：
```
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
```
> 组件含义：`main` 自由软件 / `contrib` 依赖非自由 / `non-free` 非自由 / `non-free-firmware` 硬件固件。新版也支持 DEB822 格式（`/etc/apt/sources.list.d/debian.sources`，字段结构）。

### 4.2 为什么常选 Debian 12 (Bookworm)
Debian 12 自带 `libllvm15`，与 Turnip 驱动包依赖匹配；Debian 13 可能缺该库，导致 `dpkg` 依赖报错。安装指定版本：
```bash
proot-distro install debian --override-alias bookworm
```

---

## 五、通用操作指南

### 5.1 `.tar.gz` 源码编译安装
```bash
tar -zxvf 文件名.tar.gz
cd 解压出的文件夹
./configure --prefix=/opt/某独立目录   # 指定独立目录方便卸载
make -j$(nproc)                        # 多核加速
sudo make install
```
> 优先看 `README`/`INSTALL`；能用 `apt` 就别编译；`--prefix` 便于日后清理。

### 5.2 调整 XFCE 分辨率
- **方法一（推荐）**：Termux-X11 应用 → `Preferences` → `Display resolution mode` 设 `Custom`/`Scaled`
- **方法二**：XFCE「设置管理器」→「显示」调整（可能需重启）
- **方法三（xrandr 临时）**：
  ```bash
  xrandr --output eDP-1 --mode 1920x1080   # 改分辨率
  xrandr --output eDP-1 --scale 1.5x1.5    # 改缩放
  ```

### 5.3 平板 QQ 文件传到 Debian
```bash
termux-setup-storage           # 授权存储权限
proot-distro login debian --bind ~/storage:/mnt/storage
```
QQ 文件默认路径：`~/storage/shared/Android/data/com.tencent.mobileqq/Tencent/QQfile_recv/`，容器内访问 `/mnt/storage/...`。

### 5.4 `virgl_test_server_android` 解析（VirGL 方案）
Termux 端运行，为容器提供 GPU 加速后端。组成：`virgl_test_server_android`（核心）+ `> /dev/null`（静默）+ `&`（后台）。流程：
```bash
termux-x11 :0 &
virgl_test_server_android > /dev/null &
proot-distro login debian --shared-tmp
# 容器内：GALLIUM_DRIVER=virpipe startxfce4
```

### 5.5 环境变量全局生效
- 临时：`export MESA_LOADER_DRIVER_OVERRIDE=zink && export TU_DEBUG=noconform`
- 永久：写入 `~/.bashrc`
- 单应用：在 `.desktop` 的 `Exec=` 行加前缀

---

## 六、问题排查与修复

### 6.1 任务栏消失 & 窗口无法拖动
- **日志**：`xfwm4-WARNING: Unsupported GL renderer (llvmpipe)`
- **原因**：xfwm4 的 OpenGL 合成与 Turnip 驱动不兼容
- **解决**：永久关闭 XFCE 合成器
  ```bash
  nano ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
  # <property name="use_compositing" type="bool" value="true"/>  →  false
  ```

### 6.2 修改脚本后整个黑屏
- **原因**：在启动脚本里误加 `xfwm4 --replace --compositor=off`，破坏了 `startxfce4` 流程
- **解决**：启动脚本只调 `startxfce4`，所有改动走配置文件

### 6.3 Locale 警告（不影响使用）
`Gtk-WARNING: Locale not supported by C library`
```bash
sudo apt install locales
sudo dpkg-reconfigure locales   # 勾选 zh_CN.UTF-8
```

### 6.4 会话管理器警告（不影响使用）
`Failed to connect to session manager` —— proot 无完整 D-Bus 会话。可忽略，或启动前 `eval $(dbus-launch --sh-syntax)`（proot 下可能不稳定）。

### 6.5 dpkg 依赖错误（缺 `libllvm15` 等）
```bash
sudo apt install libvulkan1            # 补依赖
sudo apt install -f                    # 修复依赖
# 或从 Debian 12 源下载对应 .deb 手动装
sudo dpkg --force-depends -i 包名.deb  # 强制安装（风险高）
```

### 6.6 启动脚本 `root: No such file or directory`
- **原因**：`su` 语法错误（如 `su` 与用户名分行）
- **解决**：proot 默认是 root，**直接去掉 `su`** 以 root 启动桌面；如需普通用户用 `su -l 用户名 -c "命令"`

### 6.7 重置 Debian
```bash
proot-distro reset debian              # 彻底删除并重装（数据全丢，先备份）
# 或 proot-distro remove debian && proot-distro install debian
```

---

## 七、GPU/CPU 任务分工与性能瓶颈

| 任务类型 | 处理单元 | 说明 |
|----------|----------|------|
| 浏览器滚动/渲染 | **GPU** | Zink→Turnip 硬件加速，流畅度明显提升 |
| 3D 应用（glmark2 等） | **GPU** | 完全 Vulkan 加速 |
| 窗口内部 UI 绘制 | **CPU** | XFCE 的 GTK/Cairo 软渲染 |
| 窗口拖动响应 | **CPU** | 关闭合成器后由 CPU 重绘，略延迟 |
| 视频解码（H.264 等） | **CPU** | Turnip 不含视频解码器，纯软解 |
| 图片解码 | **CPU** | 仅 GPU 参与缩放渲染 |
| 最终显示合成 | **GPU** | termux-x11 通过 OpenGL/Vulkan 输出 |

**瓶颈**：✅ 交互（滚动/点击）因 GPU 加速质变；❌ 视频播放靠 CPU 软解，1080p 高码率会卡；❌ 窗口拖动因关合成器略延迟。

---

## 八、验证硬件加速是否生效

```bash
# 检查 OpenGL 渲染器（最可靠）
glxinfo | grep "OpenGL renderer string"
# 成功：zink (Turnip Adreno (TM) 6xx) / VirGL
# 失败（软模拟）：llvmpipe / softpipe

# 检查 Vulkan（可选）
vulkaninfo --summary

# 跑分
glmark2
```
安装测试工具：`sudo apt install mesa-utils glmark2`

---

## 九、安卓平板 Linux 方案一览

| 方案 | 工具 | 特点 | Root |
|------|------|------|------|
| 终端模拟器 | Termux | CLI 好，GUI 需自行配 | 否 |
| PRoot（本方案） | Andronix, UserLAnd | 无 Root、便携、性能有损耗 | 否 |
| LXC 容器 | Droidspaces, Lindroid | 近乎原生性能 | 通常需 |
| 完整虚拟机 | Podroid, Vectras VM | 隔离好、开销大 | 否 |
| 系统替换 | Droidian | 原生 Linux 性能 | 需解锁 BL |

---

## 十、常用命令速查

| 用途 | 命令 |
| :--- | :--- |
| 登录容器 | `proot-distro login debian` |
| 共享 tmp | `proot-distro login debian --shared-tmp` |
| 启动 Termux-X11 | `termux-x11 :1 &` |
| 启动 VirGL 服务 | `virgl_test_server_android > /dev/null &` |
| 启动 XFCE | `env DISPLAY=:1 startxfce4` |
| 检查渲染器 | `glxinfo \| grep "OpenGL renderer"` |
| 强制装 .deb | `sudo dpkg --force-depends -i 包名.deb` |
| 修复依赖 | `sudo apt install -f` |
| 重置容器 | `proot-distro reset debian` |

---

## 十一、关键文件路径
- XFCE 配置：`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml`
- 启动脚本：`/data/data/com.termux/files/usr/bin/sx11u`
- Vulkan ICD：`/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json`

---

## 小结

本方案核心是在**无 Root 的 proot 容器**中，通过 `mesa-vulkan-kgsl` 驱动 + **Zink** 转换层，让高通 Adreno GPU 以 Vulkan 方式为 OpenGL 应用提供硬件加速。虽视频解码仍受限于 CPU，但桌面操作、网页浏览流畅度已有本质提升。

配置关键点：
1. ✅ 安装匹配 Debian 12 的 Turnip 驱动包
2. ✅ 启动脚本正确传递 `MESA_LOADER_DRIVER_OVERRIDE=zink` 和 `TU_DEBUG=noconform`
3. ✅ 关闭 XFCE 合成器解决窗口管理器兼容问题
4. ✅ 所有修改走配置文件，避免破坏 `startxfce4` 启动流程

> 排错顺序：先 `echo $变量名` 确认环境变量传递 → 再看 `glxinfo` 确认渲染器 → 最后按具体报错调整。
