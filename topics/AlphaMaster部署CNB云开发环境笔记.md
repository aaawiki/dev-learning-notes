# AlphaMaster 部署 CNB 云开发环境学习笔记

> 日期：2026-07-31
> 标签：`CNB` `云开发环境` `Docker` `FastAPI` `Python部署` `AlphaMaster`
> 类型：主题笔记（部署实战）

---

## 1. CNB 的定位

CNB 主要提供：

- Git 代码托管
- CI/CD 云原生构建
- Docker 制品库
- 临时云开发环境和端口预览

> **关键认知**：云开发环境会在空闲后**回收**，不适合作为长期在线的生产服务器。长期运行应使用 CNB **构建镜像**，再部署到云服务器或 Kubernetes。

---

## 2. 云端服务监听地址

本地开发通常监听：

```
127.0.0.1
```

但容器外部**无法访问**这个地址。CNB 中必须监听：

```bash
python run_web.py --host 0.0.0.0 --port 8765
```

其中：

- `0.0.0.0`：接受容器所有网络接口的请求
- `8765`：应用监听端口

CNB 的 **PORTS 面板**负责把容器端口映射成 `cnb.run` 地址：在 WebIDE 中按 `Ctrl+J` 打开底部面板，选择 **PORTS**，添加 `8765`。

---

## 3. Python 依赖管理

❌ 不要分别执行：

```bash
pip install fastapi
pip install pandas
pip install torch
```

✅ 应统一维护在 `requirements.txt`：

```bash
python -m pip install -r requirements.txt
```

这样可以保证**开发环境、CNB、生产环境**安装相同依赖。

> 项目训练评分还使用了 SciPy，因此补充了：`scipy>=1.10.0`

---

## 4. Linux 与 Windows 依赖差异

MetaTrader5 目前只有 Windows 安装包，CNB 使用 Linux，直接安装会失败。

使用 Python 环境标记：

```
MetaTrader5>=5.0.45; platform_system == "Windows"
```

效果：

- Windows：自动安装 MetaTrader5
- Linux / CNB：自动跳过

> 注意：CNB 上**不能直接运行 MT5 终端**。CNB 可使用 Parquet、TradingView 等数据源替代。

---

## 5. `$DISPLAY` 错误原因

错误：

```
no display name and no $DISPLAY environment variable
```

原代码使用了 Tkinter：

```python
tk.Tk()
filedialog.askopenfilename()
```

Tkinter 的文件窗口是在**服务器上**打开的。CNB 容器没有图形桌面，因此无法显示窗口。

**正确的 Web 架构是：**

```
用户浏览器选择文件
        ↓
HTTP multipart 上传
        ↓
FastAPI 接收 UploadFile
        ↓
服务器保存并校验 Parquet
```

现在数据文件会通过浏览器上传到 `data/uploads/`。上传过程采用**分块写入、Parquet 校验和原子替换**，避免大文件全部进入内存或上传失败后留下损坏文件。

---

## 6. 一键启动脚本

项目新增 `start_cnb.sh`，在 CNB 终端运行：

```bash
bash start_cnb.sh
```

脚本会自动：

1. 查找 Python 3
2. 检查 Python 版本是否达到 3.10
3. 初始化 pip
4. 执行 `pip install -r requirements.txt`
5. 启动 `0.0.0.0:8765`

指定其他端口：

```bash
bash start_cnb.sh 8686
```

也可以使用环境变量：

```bash
PORT=8686 HOST=0.0.0.0 bash start_cnb.sh
```

> 已经安装的依赖会被 pip 判断为满足要求，**不会重复完整下载**。

---

## 7. 部署更新流程

本地修改后需要提交并推送：

```bash
git add .
git commit -m "支持 CNB 云端运行"
git push origin master
```

CNB 已打开的工作区执行：

```bash
git pull
bash start_cnb.sh
```

然后浏览器按 `Ctrl+F5` **强制刷新**静态资源。

---

## 8. 数据持久化与安全

以下内容被 Git 忽略，不会随代码推送：

```
checkpoints/
data/
*.parquet
strategies/*.json
web_settings.json
```

> CNB 环境回收后，这些运行数据**可能丢失**，应使用训练包导出、对象存储或持久化磁盘保存。

> ⚠️ **安全提醒**：当前 Web 服务**没有登录认证**，并且配置接口可能返回 API Key。不要把包含真实交易凭据或 AI 密钥的服务公开给不可信用户。

---

## 核心要点速记

| 主题 | 一句话 |
|------|--------|
| CNB 定位 | 临时云开发环境会回收，长期运行要用镜像部署 |
| 监听地址 | 云端必须 `0.0.0.0`，不是 `127.0.0.1`；端口在 PORTS 面板映射 |
| 依赖管理 | 统一用 `requirements.txt`，别分开 `pip install` |
| 平台差异 | `MetaTrader5; platform_system == "Windows"` 让 Linux 自动跳过 |
| GUI 错误 | `$DISPLAY` 是没有图形桌面，改用浏览器上传 + FastAPI `UploadFile` |
| 启动脚本 | `start_cnb.sh` 一键装依赖起服务，支持端口/环境变量参数 |
| 更新流程 | 本地 `push` → CNB 里 `git pull` + `bash start_cnb.sh` → 浏览器强刷 |
| 安全 | 数据会被回收/忽略；无认证的服务别暴露密钥 |
