# Docker 打包 Windows GUI 程序实战 Checklist（MT4/MT5 跟单器）

> 日期：2026-07-21
> 标签：`Docker` `Wine` `xrdp` `Linux网络` `Shell` `容器化部署`
> 类型：主题笔记（实战 Checklist + 复盘）

---

## 背景

这次对话围绕「把 MT4/MT5 跟单器打包成 Docker 镜像，让任何人一键部署」展开，经历了完整的**构建 → 调试 → 部署 → 修复 → 推送**流程。这份笔记基于对话中实际踩过的坑和最终确定的方案，总结了把项目打包到 Docker 的基本步骤与关键经验，适合「Windows GUI 程序 + Wine + 远程桌面」类项目，也适合普通后端项目。

---

## 技术点一览

| 技术栈 | 具体内容 |
|--------|----------|
| **Docker** | 多阶段构建、layer 缓存优化、`--network host`、docker compose、volume 持久化、ghcr.io 推送 |
| **Linux** | iptables NAT 规则（PREROUTING/OUTPUT 链）、/tmp 权限冲突、X11 认证（XAUTHORITY、MIT-MAGIC-COOKIE） |
| **Wine** | wine prefix 机制、wineserver 进程模型、xvfb-run 临时显示冲突、c0000135 (DLL_NOT_FOUND) 排查 |
| **xrdp** | sesman/sesexec 进程模型、dbus-launch 依赖、XFCE 桌面集成 |
| **Shell** | here-doc 转义陷阱、su -c 引号层级、路径空格问题、script 模板模式 |
| **GitHub** | Git push、ghcr.io 镜像仓库、Package visibility、Token scope 权限 |

---

## 最有价值的三次排查

### 1. iptables 规则导致容器无网络

- **症状**：`apt-get update` 报 Connection refused 到 deb.debian.org:80
- **排查链**：容器 bridge 出站 → PREROUTING 链 → 全局 `tcp dpt:80 REDIRECT 8080` → 容器发出的 80 端口请求被劫持到宿主机 8080
- **修复**：`-A PREROUTING -i ens5 -p tcp --dport 80 -j REDIRECT --to-ports 8080` 加上 `-i ens5` 限定仅外部网卡

### 2. `kernel32.dll c0000135` 反复出现

- **症状**：`wine --version` 成功，`wineboot` 创建新 prefix 成功一次后再次运行就报错
- **根因**：entrypoint 中的 `xvfb-run wineboot` 创建了绑定在临时 X 显示上的 wineserver 进程。用户 xrdp 的 `:10` 和 xvfb 的临时显示不是同一个，wineserver 状态冲突导致 DLL 加载失败。
- **修复**：构建时预初始化 prefix 保存为 template（`/opt/wine-template/`），启动时只复制，**不运行 wineboot**。

### 3. xrdp 桌面双击 exe 无反应 + "dbus-launch not found"

- **根因**：Dockerfile 用了 `--no-install-recommends`，导致 `dbus-x11` 包被跳过，XFCE 无法启动 session。
- **修复**：显式安装 `dbus-x11`，并从 xrdp 终端用 `wine /tmp/mt5setup.exe` 替代双击。

---

## 对学习计算机的帮助

> 这段对话的价值不在于"做出了一个镜像"，而在于演示了一个**真实的工程迭代过程**——不是写一次就成功，而是反复试错、阅读日志、缩小范围、锁定根因、再修改。

- **故障排查能力**：三次关键排查都遵循同一模式 →「观察症状 → 缩小范围 → 验证假设 → 修正」。这种思维比具体技术更通用。
- **Docker 实战**：layer 缓存策略、volume 覆盖镜像文件的坑、entrypoint 与 volume 初始化的时序关系，这些都是文档里很少提到的实战经验。
- **Linux 网络排障**：iptables PREROUTING vs OUTPUT 链的作用域区别、nf_tables 与 legacy iptables 的行为差异，理解这些对任何后端开发都有用。
- **Wine/Windows 兼容层**：了解 Wine prefix 隔离机制、wineserver 的单例模型、为什么多个 Wine 进程共享状态会互相干扰。
- **Shell 工程化**：heredoc 转义、su -c 多层引号、变量中空格的处理，这些是写自动化脚本时常见的坑。

---

## 通用 Docker 打包 Checklist

### 一、打包前的准备工作

1. **明确运行时依赖**
   - 本例：Wine 11.0、Win32/Win64 依赖、Python 3.13（Windows embeddable）、MetaTrader5 库
   - 通用法：把所有依赖写在 `requirements.txt`（或 `package.json` 等）里，用包管理器安装而非手动拷贝

2. **确定启动逻辑**
   - 本例：先初始化 Wine 前缀 → 恢复 MT5/MT4 → 启动 Copier 服务
   - 通用法：用 `entrypoint.sh` 把所有启动步骤写进去，而不是让用户手动操作

3. **验证所有资源可下载**
   - 本例：MT5/MT4 安装程序从官方 mql5 CDN 下载
   - 通用法：外部下载用 `wget --show-progress` 并加重试逻辑（`for i in 1 2 3`）

---

### 二、Dockerfile 编写要点

| 要点 | 怎么做 |
|------|--------|
| **基础镜像** | 用 `debian:bookworm-slim`（小体积），不要用 Ubuntu（太大） |
| **apt 源** | 先清理 `/etc/apt/sources.list.d/*`，重新写入 debian 主源和安全更新源 |
| **多架构** | `dpkg --add-architecture i386`（Win32 程序需要） |
| **依赖精简** | 用 `--no-install-recommends`，但要**手动加常见缺失包**（本例：`dbus-x11`） |
| **layer 顺序** | 从「最不常变」到「最常变」：系统依赖 → Wine → Python → 项目文件 |
| **权限** | 所有 `wine` 操作必须用同一个用户（本例：`trader`），不要 root 和普通用户混用 |

#### 关键 Lesson：Volume 会覆盖镜像文件

```dockerfile
# ❌ 错误：把数据放在会被 volume 挂载的路径
RUN cp mydata /home/trader/.wine/drive_c/myapp/

# ✅ 正确：放在不会被覆盖的路径，等 container 启动时复制过去
RUN cp mydata /opt/myapp-backup/
```

---

### 三、Entrypoint 设计（最重要的部分）

#### 核心原则

> 构建时做「初始化」，启动时做「恢复」。不要在启动时跑需要 GUI 的东西。

#### 设计模式

```text
entrypoint.sh:
  1. chown 关键目录（快速）
  2. 检查 volume 是否为空
     ├─ 空   → 从 /opt/ 恢复 prefix 模板
     └─ 非空 → 跳过
  3. 启动 Xvfb（:99）供后台 Wine 服务使用
  4. 启动 xrdp（:10）供用户远程桌面使用
  5. 启动后台服务（MT5/MT4/Copier）在 :99
  6. 保持容器运行
```

#### 教训：不要在 entrypoint 中运行 `wineboot`

```text
❌ xvfb-run -a wineboot -u      # 会残留 wineserver，和 xrdp 桌面冲突
✅ 构建时跑一次 wineboot，把 prefix 保存为模板；启动时只复制
```

---

### 四、iptables 配置（仅宿主机的 Copier 端口转发）

**背景**：Copier 监听的 8080 端口需要宿主机 80 端口转发过去。

```bash
# ❌ 错误：全局 REDIRECT 会劫持容器出网流量
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 8080

# ✅ 正确：限制接口范围
iptables -t nat -A PREROUTING -i ens5 -p tcp --dport 80 -j REDIRECT --to-ports 8080
iptables -t nat -A OUTPUT -d 127.0.0.1 -p tcp --dport 80 -j REDIRECT --to-ports 8080
```

最后用 `iptables-save > /etc/iptables/rules.v4` 持久化。

---

### 五、测试和验证

| 验证项目 | 命令 |
|----------|------|
| Docker 构建 | `docker build -t 镜像名:latest -f docker/Dockerfile .` |
| 容器运行 | `docker run -d --name test -p 3389:3389 -p 8080:8080 -v data_vol:/path 镜像名` |
| 查看日志 | `docker logs test --tail 20` |
| 检查进程 | `docker exec test ps aux` |
| 检查文件 | `docker exec test ls -la /opt/mt-backups/` |
| 网络测试 | `curl -s http://127.0.0.1:8080/health` |
| 远程桌面 | 用 RDP 客户端连接 `IP:3389` |

---

### 六、发布到 GitHub Container Registry

#### 先确保能成功构建

```bash
sudo docker build -t mt4-mt5-copier:latest -f docker/Dockerfile .
```

#### 推送三步骤

```bash
# 1. 登录（需要 GitHub PAT，scope 勾选 write:packages）
echo "你的TOKEN" | docker login ghcr.io -u 用户名 --password-stdin

# 2. 打标签
docker tag mt4-mt5-copier:latest ghcr.io/用户名/仓库名:latest

# 3. 推送
docker push ghcr.io/用户名/仓库名:latest
```

#### 需要注意

- 需要 GitHub PAT 勾选 `write:packages`（只有 `repo` 不够）
- 推完默认是**私有**的，需要去 GitHub Package settings 设为 Public

---

### 七、最终能用的完整命令（可直接复制执行）

```bash
# 拉取
docker pull ghcr.io/用户名/仓库名:latest

# 启动
docker run -d --name mt4-copier \
  -p 3389:3389 -p 8080:8080 \
  -v mt4_data:/home/trader/.wine \
  ghcr.io/用户名/仓库名:latest

# xrdp 登录 → 用户名/密码：trader / trader
# 终端中手动装 MT5/MT4（仅首次，约 2 分钟）
wine /opt/mt5setup.exe   # 点 Next → Install → Finish
wine /opt/mt4setup.exe   # 同上

# 输入以下两行后服务会启动：
wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v ucrtbase /t REG_SZ /d "native,builtin" /f
bash /home/trader/mt4_copier/start.sh

# 验证
curl http://127.0.0.1:8080/health
```

> **提示**：只安装一次 MT5/MT4；后续启动只需要最后两行（以及登录 MT5/MT4 账户）。
