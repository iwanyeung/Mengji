# MengjiWatch（v1.1 Phase 1）

## 手动验收清单

1. **配对与安装**：iPhone 已安装梦悸 Debug/Release，Watch 上出现「梦悸」；首次打开授予麦克风与通知。
2. **多段录音**：点击黄钮开始 → 再点结束 → 显示「本段已传到手机…」→ 可继续录第二段（同一场梦复用 dreamId）。
3. **手机草稿池**：每段到达后 iPhone 录梦 Tab 出现对应草稿（来源「手表」），**不**自动进梦析。
4. **手机整理**：勾选要参与的段（含手机自录段）→「完成并整理」→ 梦析成功 → 手表轻微震动 + 腕上通知「梦析已完成」。
5. **四格落成**：漫画生成完成后，手表震动 + 通知「四格已落成」（手机前台生成或远程推送均可）。
6. **断连排队**：飞行模式录梦，恢复蓝牙后应自动 `transferFile` 送达（系统队列）。
7. **权限拒绝**：拒绝麦克风后显示「需要麦克风权限」，不崩溃。
8. **新一场梦**：手机录梦页点「新一场梦」清空草稿，手表下一段使用新会话。

## 真机安装（Watch 装不上时）

### 可忽略的 Xcode 报错

若 Report Navigator 里只有：

`Failed with HTTP status 403: forbidden` · `DataGatheringNSURLSessionDelegate`

这是 **Xcode 向 Apple 上报诊断/遥测数据被拒**，与 App 签名、Watch 安装 **无关**，可忽略。请在同一日志里找 `installd`、`ApplicationVerificationFailed`、`WatchKit` 等关键字。

### 推荐流程

1. **Apple Watch** 开启：设置 → 隐私与安全性 → **开发者模式**（需重启手表）
2. Xcode：**Project + MengjiApp + MengjiWatch** 三个 Target 的 **Team 均为同一团队**（`22G8NT8SD8`）
3. iPhone **删除梦悸** → Product → **Clean Build Folder** → Scheme 选 **MengjiApp**，运行目标必须选 **Jingran 的 iPhone**（不要只选手表）→ **⌘R**（会装手机 App，并尝试同步装手表伴侣）
4. **Window → Devices and Simulators** → 选中 iPhone → Installed Apps → 梦悸 → 确认有 **Watch App** 子项
5. 若仍未自动装上：iPhone「Watch」App → 梦悸 → 打开「在 Apple Watch 上显示 App」
6. Debug 控制台应出现：
   - `[WatchDiag] iPhoneBundleHasEmbeddedWatch=true`
   - `[WatchIngest] ... isWatchAppInstalled=true`
7. 若 `iPhoneBundleHasEmbeddedWatch=true` 但 `isWatchAppInstalled=false`：在 iPhone「Watch」打开安装开关，并在 **Mac Console 选 iPhone（不是手表）** 搜 `installd` 或 `watchkitapp`（不要搜 `installed`）
8. 手动双端安装：`chmod +x scripts/install-mengji-to-devices.sh` 后  
   `./scripts/install-mengji-to-devices.sh <iPhoneID> <手表ID>`

### 验证 iPhone 包是否含 Watch

Run 成功后于 Mac 终端执行：

```bash
find ~/Library/Developer/Xcode/DerivedData/MengjiApp-*/Build/Products/Debug-iphoneos/MengjiApp.app -path "*/Watch/MengjiWatch.app"
```

有输出路径 = 嵌入成功；无输出 = 先修构建/Embed，不要反复在 Watch App 里点开关。

## 架构

- 手表：`AVAudioRecorder` → `WCSession.transferFile`（多段、同 dreamId）
- 手机：`WatchDreamIngestService` → `DreamRecordingSession` 草稿池 → 用户勾选 → `DreamService` 上传与梦析
- 通知：手机 `WatchNotificationBridge` → 手表 `WatchNotificationHandler`（震动 + 本地通知）；服务端 `dream_analyzed` / `visual_done` APNs 兜底
