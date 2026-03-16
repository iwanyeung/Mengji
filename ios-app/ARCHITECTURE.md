## 梦悸 iOS SwiftUI 架构骨架

> 说明：此文档配合未来在 Xcode 中创建的 `MengJiApp` 工程使用，定义模块划分、导航结构与服务抽象。

### 1. 顶层结构

- `MengJiAppApp.swift`：应用入口，根视图为 `RootTabView`。
- `App/`
  - `RootTabView.swift`：包含四个主 Tab 的 `TabView`。
  - `AppTheme.swift`：颜色与字体（映射 PRD 中的设计 token）。
  - `AppServices.swift`：依赖注入入口，提供各模块共享的服务实例。

### 2. 模块划分

- `Modules/Recording/`
  - `RecordingView.swift`：录梦主界面（对应 HTML `1-code.html`）。
  - `RecordingViewModel.swift`：管理录音状态、分段列表、本地缓存。
- `Modules/Insight/`
  - `InsightListView.swift`（可选）：梦列表或最近梦摘要。
  - `InsightDetailView.swift`：单条梦的梦析页。
  - `InsightViewModel.swift`。
- `Modules/Workshop/`
  - `WorkshopEntryView.swift`：显化工坊入口，选择梦与风格。
  - `FourPanelResultView.swift`：四格漫画结果页面。
- `Modules/StarMap/`
  - `StarMapView.swift`：潜意识星图画布（基于 `Canvas`）。
  - `StarMapViewModel.swift`：管理节点与边的数据。
- `Modules/Settings/`
  - `SettingsView.swift`：档案与声明等。

### 3. TabView 结构（示意）

```swift
struct RootTabView: View {
    enum Tab {
        case recording
        case insight
        case workshop
        case starMap
    }

    @State private var selection: Tab = .recording

    var body: some View {
        TabView(selection: $selection) {
            RecordingView()
                .tabItem {
                    Image(systemName: "mic.fill")
                    Text("录梦")
                }
                .tag(Tab.recording)

            InsightRootView()
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("梦析")
                }
                .tag(Tab.insight)

            WorkshopRootView()
                .tabItem {
                    Image(systemName: "photo.on.rectangle")
                    Text("显化工坊")
                }
                .tag(Tab.workshop)

            StarMapView()
                .tabItem {
                    Image(systemName: "square.stack.3d.down.right")
                    Text("潜意识星图")
                }
                .tag(Tab.starMap)
        }
        .accentColor(AppTheme.primaryColor)
    }
}
```

### 4. Theme 映射（示意）

```swift
enum AppTheme {
    static let primaryColor = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x33 / 255)
    static let background = Color(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0F / 255)
    static let surface = Color(red: 0x1E / 255, green: 0x1A / 255, blue: 0x25 / 255)
    static let text = Color(red: 0xF4 / 255, green: 0xF0 / 255, blue: 0xEB / 255)
    static let muted = Color(red: 0x7A / 255, green: 0x75 / 255, blue: 0x85 / 255)
}
```

### 5. 服务层抽象

- `Shared/Services/AuthService.swift`
- `Shared/Services/DreamService.swift`
- `Shared/Services/VisualService.swift`
- `Shared/Services/GraphService.swift`

每个 Service 负责组装对应的 REST API 请求，与 `server/docs/api.md` 中定义的接口一一对应。

