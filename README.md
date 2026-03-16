## 梦悸（Dream Impulse）MVP

本仓库包含梦悸 iOS App MVP 及后端服务的代码与文档，实现从「录梦 → 梦析 → 显化工坊（四格漫画） → 潜意识星图」的完整闭环。

### 仓库结构

- `ios-app/`：iOS 客户端（Swift + SwiftUI），包含底部四个 Tab：「录梦 / 梦析 / 显化工坊 / 潜意识星图」。
- `server/`：后端服务（TypeScript + Node.js + Express），封装 See Dance 能力并对 iOS 暴露 REST API。
- `docs/`：产品文档（如 `docs/PRD.md`）。

### 技术栈约定

- **iOS**：Swift 5+，SwiftUI，MVVM 风格；后续可根据需要演进为 TCA。
- **Server**：Node 20+，TypeScript，Express；后续可根据规模演进为 NestJS 或微服务架构。
- **部署**：后端部署在腾讯云（CVM / Serverless 均可），通过 HTTPS 对外提供 API；所有 See Dance 调用仅在服务端进行。

### 快速开始（占位）

后续在分别完成 `ios-app` 与 `server` 初始化后补充：

- 如何在 Xcode 中打开 `ios-app`。
- 如何安装依赖并运行 `server`。

