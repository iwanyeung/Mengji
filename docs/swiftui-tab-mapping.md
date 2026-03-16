## HTML TabBar 与 SwiftUI TabView 映射说明

本文档用于对齐当前 HTML 原型中的底部导航与未来 iOS SwiftUI 实现，确保导航结构与视觉语言统一。

### 1. Tab 列表与文案对应

- Tab1：`录梦` → SwiftUI 模块：`RecordingModule`
- Tab2：`梦析` → SwiftUI 模块：`InsightModule`
- Tab3：`显化工坊` → SwiftUI 模块：`WorkshopModule`
- Tab4：`潜意识星图` → SwiftUI 模块：`StarMapModule`

HTML 中四个 Tab 的顺序与文案必须与 SwiftUI `TabView` 中的顺序一致。

### 2. 图标映射

当前 HTML 使用的 Material Symbols 图标只是预览占位，SwiftUI 中建议映射为：

- `录梦`：录音/麦克风类图标（如 SF Symbols 的 `mic.fill`）
- `梦析`：星光/解析类图标（如 `sparkles` 或 `text.book.closed`）
- `显化工坊`：图像/画布类图标（如 `photo.on.rectangle`）
- `潜意识星图`：档案/图谱类图标（如 `square.stack.3d.down.right` 或 `circle.grid.2x2`）

SwiftUI 中可通过 `Image(systemName: "mic.fill")` 等方式引入。

### 3. 状态与激活态规则

- HTML：
  - 通过 `mj-tab--active` 类控制当前页面的激活态，颜色为 `#D4FF33`。
  - 其他 Tab 使用 `#7A7585` 作为未激活颜色。
- SwiftUI：
  - 使用 `TabView(selection:)` 管理当前选中 Tab，与枚举值（如 `Tab.record`, `Tab.insight` 等）绑定。
  - 激活态颜色可通过 `tint(Color.primary)` 或自定义 TabBar 视图实现，与 HTML 中的酸性黄保持一致。

### 4. 交互行为对齐

- HTML：
  - 每个 Tab 是一个 `<a>` 元素，通过 `href` 在不同页面之间跳转。
  - 语义上模拟“点击底部 Tab 切换根页面”的行为。
- SwiftUI：
  - 使用 `TabView`，确保点击任一 Tab 时重置到对应模块的根视图（而非继续叠栈）。
  - 各模块内部再使用 `NavigationStack` 管理详情跳转。

### 5. 视觉与布局原则

- 背景与边框：
  - HTML TabBar：`background: rgba(13, 12, 15, 0.96)`，顶部 1px 边框使用 `rgba(122, 117, 133, 0.4)`。
  - SwiftUI 中可通过自定义容器视图，使用相同颜色值构造一个固定在底部的栏。
- 字体与排版：
  - HTML 使用 10px、大写、`letter-spacing: 0.16em`。
  - SwiftUI 建议使用 `Font.system(size: 10, weight: .semibold, design: .default).tracking(0.16)` 并 `textCase(.uppercase)`。

### 6. 文件与组件对应关系

- HTML：
  - TabBar 已集成在 `MVP/_1/1-code.html` ~ `MVP/_4/4-code.html` 中，类名为 `mj-tabbar`、`mj-tabbar-inner`、`mj-tab`、`mj-tab--active`。
- SwiftUI：
  - 建议创建一个 `MengjiTabBar` 自定义视图或直接使用系统 `TabView`，但在 `tabItem` 中对图标和文字进行与 HTML 对齐的定制。

通过以上映射，浏览器中的 HTML 原型可以作为 SwiftUI 实现的视觉与交互参考，使两端在导航体验上保持高度一致。

