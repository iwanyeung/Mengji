# 梦悸 CVM SSH 配置

CVM：**49.233.91.206**（内网 172.21.0.6）

## 已在 Mac 上配置

`~/.ssh/config` 中 Host 别名：

```bash
ssh mengji-cvm
```

默认使用项目内密钥：`mengjiSSH.pem`（用户 `ubuntu`）

## 若 `Permission denied (publickey)`

说明 CVM **尚未绑定**当前私钥对应的公钥，请在腾讯云控制台操作其一：

### 方式 A：绑定下载的 `.pem` 密钥（推荐）

1. [腾讯云控制台](https://console.cloud.tencent.com/cvm/instance) → 实例 → 选中该 CVM
2. **更多** → **密码/密钥** → **加载密钥**
3. 选择与 `mengjiSSH.pem` **同名**的 SSH 密钥（创建实例时若选了别的密钥，需重新加载或重建密钥对）
4. **安全组** 放行 **22** 端口（来源可先填你的 Mac 公网 IP）
5. 本机验证：

```bash
chmod 600 /Users/iwan/Desktop/Mengji/mengjiSSH.pem
ssh mengji-cvm "echo ok"
```

### 方式 B：绑定本地 ed25519 公钥

将 `~/.ssh/mengji_cvm.pub` 内容添加到 CVM 的 `~/.ubuntu/.ssh/authorized_keys`（需先用控制台 **VNC/标准登录** 进一次），或在控制台 **绑定自定义公钥**。

绑定成功后可用：

```bash
ssh mengji-cvm-ed25519 "echo ok"
```

## Cursor Agent 常用命令

```bash
# 检查连通
ssh mengji-cvm "uname -a"

# 上传邀请码
scp server/data/invite-codes-beta-20250603.sql mengji-cvm:/tmp/

# 健康检查（部署后）
curl http://49.233.91.206/health
```

## 安全提醒

- **切勿**将 `*.pem` 提交到 Git（已加入 `.gitignore`）
- 建议将 `mengjiSSH.pem` 移到 `~/.ssh/mengjiSSH.pem` 并更新 `IdentityFile`
