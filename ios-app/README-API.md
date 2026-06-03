## iOS 对接后端

### 本地开发

1. 启动 `server/`（见 `server/README.md`），默认 `http://127.0.0.1:3000`
2. **模拟器**：Debug 构建默认连 `127.0.0.1:3000`（或通过 Info.plist 中的局域网地址）
3. **真机 + Mac 本地 API**（已配置）：
   - Debug 构建自动读取 `Config/Debug.xcconfig` 中的 `MENGJI_DEV_API_BASE`
   - `Info-Additions.plist` 已开启 `NSAllowsLocalNetworking` 与 `NSLocalNetworkUsageDescription`
   - 首次运行若弹出「本地网络」权限，请选择允许；也可在 **设置 → 隐私与安全性 → 本地网络** 中开启梦悸
   - Scheme 已关联 `Products.storekit`（内购本地测试）

### Staging（CVM 公网 IP，当前默认）

1. API 地址：`http://49.233.91.206`（`Config/Debug.xcconfig` + Scheme 环境变量）
2. `Info-Additions.plist` 已为 `49.233.91.206` 配置 ATS HTTP 例外（内测用）
3. 验收：`curl http://49.233.91.206/health`
4. 改回 Mac 本地：将 `MENGJI_DEV_API_BASE` 改为 `http://192.168.x.x:3000`

### 生产（TestFlight / App Store）

1. 域名备案完成后，在 `Info.plist` 修改 `MENGJI_API_BASE` 为 HTTPS API 地址，例如：
   ```
   https://api.yourdomain.com
   ```
2. 或通过 Xcode Build Settings / xcconfig 注入，Release 构建时覆盖默认值

### StoreKit

- 本地测试：Xcode 关联 `Products.storekit`（商品 ID `com.mengji.visual.four_panel_once`）
- ASC 审核通过后：App Store Connect 创建同名 Consumable 商品

### 邀请码

```bash
cd server && npm run invite:generate -- --count 100 --batch beta-100
```

App「个人中心 → 邀请体验」兑换（需 **真实 Apple 登录**，DEBUG 模拟登录无法兑换）。

### 全链路验收清单

- [ ] 录梦 → 上传音频 → 梦析（DeepSeek 真实响应）
- [ ] Apple 登录 → 邀请码兑换 → 显示 10 次免费额度
- [ ] 显化工坊 → 四格漫画生成（Seedream，约 1–3 分钟）
- [ ] ASC 就绪后：Sandbox IAP 购买 → 四格生成
