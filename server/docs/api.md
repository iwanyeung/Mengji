# 梦悸 MVP API 概要（草案）

> 面向 iOS 客户端，覆盖录梦、梦析、显化工坊、潜意识星图与账号能力。具体字段可在实现时按需微调。

## 认证与用户

### POST /api/auth/anonymous

创建或获取一个匿名访客用户。

- 请求体：

```json
{
  "deviceId": "string"
}
```

- 响应体：

```json
{
  "token": "jwt-or-session-id",
  "user": {
    "id": "user-id",
    "authProvider": "anonymous"
  }
}
```

### POST /api/auth/apple

使用 Apple 登录绑定账号，合并本机游客数据。

### POST /api/auth/wechat

使用微信登录绑定账号，合并本机游客数据。

## 录梦与分段转写

### POST /api/dreams

创建一条新的梦记录，用于开始录制。

- 请求体：

```json
{
  "occurredAt": "2025-03-16T03:14:00Z",
  "source": "iphone"
}
```

- 响应体：

```json
{
  "id": "dream-id",
  "status": "recorded"
}
```

### POST /api/dreams/{dreamId}/segments

上传一个录音分段并触发 ASR 转写。

- 请求：
  - Content-Type: multipart/form-data
  - 字段：
    - `audio`: 音频文件（m4a / caf 等）
    - `index`: 分段序号（从 0 或 1 开始）

- 响应体：

```json
{
  "segmentId": "segment-id",
  "index": 0,
  "durationSeconds": 32,
  "transcript": "这一段是我在……"
}
```

### POST /api/dreams/{dreamId}/finalize-recording

结束录制，通知后端可以开始梦境整理与梦析任务。

- 响应体：

```json
{
  "id": "dream-id",
  "status": "transcribed"
}
```

## 梦析（整理 + 标签 + 解读）

### GET /api/dreams/{dreamId}

获取某条梦的完整信息，用于“梦析”页展示。

- 响应体（示例）：

```json
{
  "id": "dream-id",
  "occurredAt": "2025-03-16T03:14:00Z",
  "status": "analyzed",
  "refinedNarrative": "AI 整理后的 1–2 段文学化文本……",
  "analysisText": "温柔陪伴式解读……",
  "segments": [
    {
      "id": "segment-id",
      "index": 0,
      "durationSeconds": 32,
      "transcript": "原始口述转写……"
    }
  ],
  "tags": [
    { "id": "tag-id-1", "name": "牙齿", "category": "object" },
    { "id": "tag-id-2", "name": "追逐", "category": "theme" }
  ],
  "visuals": [
    {
      "id": "visual-id",
      "type": "four_panel_comic",
      "status": "succeeded",
      "imageUrl": "https://..."
    }
  ]
}
```

## 显化工坊（四格漫画）

### POST /api/dreams/{dreamId}/visuals/four-panel

创建一个四格漫画显化任务（通常在支付成功后调用）。

- 请求体（示例）：

```json
{
  "styleKey": "high_contrast_bw",
  "paymentReference": "apple-iap-receipt-or-wechat-order-id"
}
```

- 响应体：

```json
{
  "visualId": "visual-id",
  "status": "queued"
}
```

### GET /api/visuals/{visualId}

轮询查看四格漫画生成状态。

- 响应体：

```json
{
  "id": "visual-id",
  "dreamId": "dream-id",
  "type": "four_panel_comic",
  "status": "generating",
  "imageUrl": null
}
```

## 潜意识星图

### GET /api/dreams/graph

获取当前用户在“潜意识星图”中需要渲染的节点与连接线。

- 可选查询参数：
  - `onlyVisualized=true`：只返回已有显化作品的梦。

- 响应体（示例）：

```json
{
  "nodes": [
    {
      "id": "dream-id-1",
      "dateLabel": "10.24",
      "tags": ["牙齿", "追逐"],
      "snippet": "牙齿在走廊里掉落……",
      "hasVisual": true,
      "position": { "x": 0.45, "y": 0.45 }
    }
  ],
  "edges": [
    {
      "id": "edge-id",
      "from": "dream-id-1",
      "to": "dream-id-2",
      "score": 0.82,
      "sharedTags": ["牙齿", "焦虑"]
    }
  ]
}
```

### GET /api/dreams/search

按关键词与标签搜索梦，用于星图下方搜索与过滤。

- 查询参数：
  - `q`: 文本关键词。
  - `tag`: 可重复的标签名或 id。
  - `hasVisual`: `true/false`。

## 账号与档案

### GET /api/me

返回当前用户基础信息与设置信息。

### PATCH /api/me

更新年龄段、性别认同、颜色偏好等资料。

