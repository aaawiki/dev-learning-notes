# AWS 云服务器管理 & Xray 代理配置笔记

## 一、密钥对文件创建

创建密钥对的三种场景及对应工具：

| 场景 | 推荐工具 | 命令 / 操作 |
|---|---|---|
| SSH 远程登录 | `ssh-keygen` (Linux/macOS) / PuTTYgen (Windows) | `ssh-keygen -t ed25519` |
| SSL/TLS 证书 | Java `keytool` | `keytool -genkeypair` |
| 文件加密签名 | GPG | `gpg --full-generate-key` |

**核心原则**：私钥严禁泄露。

---

## 二、AWS Debian 13 服务器 Root 密码管理

### 现状
- AWS 默认禁止 root 密码登录，且未设置密码
- 需通过密钥登录默认用户（如 `admin`）

### 设置/修改 root 密码

| 场景 | 方法 |
|---|---|
| 常规（已有密钥登录） | 登录后执行 `sudo passwd root` |
| 新实例自动化 | 在"用户数据"中写入脚本设置密码 |
| 紧急救援（丢失密钥） | 挂载 EBS 卷到救援实例，`chroot` 修改 |

### 开启 root 直接 SSH 登录（不推荐）
修改 `/etc/ssh/sshd_config`：
```
PermitRootLogin yes
PasswordAuthentication yes
```
然后重启 SSH 服务。**安全性低，强烈不推荐。**

---

## 三、Xray 启动日志中的"弃用"警告

### 现象
```
[Warning] VMess 和 WebSocket 协议被标记为弃用
```

### 定性
- 仅为远期规划提醒，**不影响当前使用**

### 升级方案

| 方案 | 路径 | 说明 |
|---|---|---|
| 方案一（稳定） | VLESS + TCP + TLS/XTLS | 带 `flow` 参数，成熟稳定 |
| 方案二（前沿） | VLESS + XHTTP | 官方推荐的新传输协议 |

### 迁移注意事项
- 需同步修改 AWS 服务端配置和 Windows 客户端配置
- 检查防火墙与证书

---

## 四、Xray 运行日志中的"连接测试"报错

### 现象
```
failed to read response from www.msftconnecttest.com
```
同时 YouTube / AWS 访问正常。

### 定性
- Windows 系统 NCSI（网络状态检测）主动访问微软测试域名导致的协议交互报错
- **不影响代理功能**

### 根治方案
在 Xray 客户端 **路由规则（routing）** 中，将以下域名指向直连出站：

```json
{
  "domain": [
    "msftconnecttest.com",
    "ipv6.msftconnecttest.com"
  ],
  "outboundTag": "direct"
}
```

### 日志标识说明
| 标识 | 含义 |
|---|---|
| `->` | 普通出站连接 |
| `>>` | 多路复用出站连接 |

---

## 关键结论
- AWS 服务器密钥登录方案和代理服务核心功能均正常运行
- 当前日志中的"报错"仅为 Windows 系统探测干扰和 Xray 未来兼容性预告，均有成熟解决方案
