## ios-app

梦悸 iOS 客户端（Swift + SwiftUI）。

> 说明：Xcode 工程文件通常通过 Xcode 创建，这里先约定目录结构与架构原则，便于后续在 Xcode 中按本结构新建项目并迁移代码。

### 预期目录结构（建议）

- `MengJiApp/`：Xcode 生成的应用 Target 代码根目录
  - `App/`：应用入口与全局配置（`MengJiApp.swift`、环境注入等）
  - `Modules/`
    - `Recording/`（录梦）
    - `Insight/`（梦析）
    - `Workshop/`（显化工坊）
    - `StarMap/`（潜意识星图）
    - `Settings/`（设置与声明）
  - `Shared/`
    - `Theme/`：颜色、字体、组件样式
    - `Components/`：通用 UI 组件（按钮、标签、卡片等）
    - `Services/`：`AuthService`、`DreamService`、`VisualService`、`GraphService` 等网络与本地服务

后续步骤：

1. 在 Xcode 中创建 SwiftUI iOS App 工程（例如名为 “MengJiApp”）。
2. 按上述结构整理 Group / 目录。
3. 在对应目录下补充 Swift 源码文件。

