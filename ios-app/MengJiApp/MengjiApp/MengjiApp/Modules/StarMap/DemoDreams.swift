import Foundation

private enum DemoDreams {
    /// 固定 ID：保证多次调用 `upsert` 不会重复插入；也便于以后识别/删除示例数据。
    private static let id1 = UUID(uuidString: "A1B2C3D4-1111-4000-8000-000000000001")!
    private static let id2 = UUID(uuidString: "A1B2C3D4-2222-4000-8000-000000000002")!
    private static let id3 = UUID(uuidString: "A1B2C3D4-3333-4000-8000-000000000003")!
    private static let id4 = UUID(uuidString: "A1B2C3D4-4444-4000-8000-000000000004")!
    private static let id5 = UUID(uuidString: "A1B2C3D4-5555-4000-8000-000000000005")!
    private static let id6 = UUID(uuidString: "A1B2C3D4-6666-4000-8000-000000000006")!

    static func makeDemoDreams(now: Date = Date()) -> [Dream] {
        // 注意：DreamStore 的 `upsert` 会以 createdAt/排序策略由星图 ViewModel 自己决定展示顺序。
        // 这里的 createdAt 仅用于制造“近/远”的粗时间轴效果。
        let d1 = now.addingTimeInterval(-60 * 60 * 24 * 1)   // 近
        let d2 = now.addingTimeInterval(-60 * 60 * 24 * 3)
        let d3 = now.addingTimeInterval(-60 * 60 * 24 * 7)
        let d4 = now.addingTimeInterval(-60 * 60 * 24 * 11)
        let d5 = now.addingTimeInterval(-60 * 60 * 24 * 18)
        let d6 = now.addingTimeInterval(-60 * 60 * 24 * 26)  // 远

        let comicArtifact = ComicArtifact(
            id: UUID(uuidString: "B0B0B0B0-0001-4000-8000-000000000001")!,
            createdAt: now.addingTimeInterval(-60 * 60 * 24 * 2),
            styleId: "neon-surreal-v1",
            previewDescription: "霓虹超现实四格：牙齿/追逐",
            imagePaths: ["mock://demo/comic_1_1.png", "mock://demo/comic_1_2.png"]
        )

        return [
            Dream(
                id: id1,
                createdAt: d1,
                rawTranscript: "我在走廊里追着一颗掉落的牙齿，它每次落下又变成烟。",
                organizedText: "走廊在拉长，我追着一颗掉落的牙齿。每当我靠近，它就化成细烟，像是把话吞回夜里。",
                interpretation: "这更像是一种“失去却想抓住”的节奏：你追赶的并不只是某个物件，而是对确定感的渴望。",
                tags: ["牙齿", "追逐", "走廊", "焦虑"],
                title: "关于「掉落的牙齿」的夜里",
                note: nil,
                isArchived: false,
                comicArtifacts: [comicArtifact]
            ),
            Dream(
                id: id2,
                createdAt: d2,
                rawTranscript: "我站在地铁入口，听到有人喊我的名字，但找不到声音从哪里来。",
                organizedText: "地铁入口像一张黑色的门。我听见有人喊我的名字，可转身时又什么都没有，只有空气在回声里打圈。",
                interpretation: "你在梦里寻找“呼应”：当注意力需要被确认时，现实缺口就会变成回声和找不到的来源。",
                tags: ["地铁", "名字", "回声", "迷失"],
                title: "关于「听不见的名字」的夜里",
                note: nil,
                isArchived: false,
                comicArtifacts: []
            ),
            Dream(
                id: id3,
                createdAt: d3,
                rawTranscript: "我在海上漂着，看到远处的城市像一盏灯。可灯忽明忽暗，像在呼吸。",
                organizedText: "海面很平，远处的城市像一盏灯。每一次眨眼，它就忽明忽暗，仿佛在用呼吸把距离拉近。",
                interpretation: "城市的灯光像“方向感”：你可能正在从不确定里寻找一种节律，让自己知道往哪里走。",
                tags: ["城市", "海上", "灯光", "呼吸"],
                title: "关于「忽明忽暗的城市」的夜里",
                note: nil,
                isArchived: false,
                comicArtifacts: []
            ),
            Dream(
                id: id4,
                createdAt: d4,
                rawTranscript: "楼梯无穷无尽，越往上越潮湿，脚步声像被吞掉。",
                organizedText: "楼梯一直延伸。潮湿沿着台阶爬上来，脚步声却像被吞回去，只剩下心跳在回荡。",
                interpretation: "无限的楼梯常出现于“需要推进却又卡住”的状态：你想往上，但又担心走丢声音。",
                tags: ["楼梯", "潮湿", "吞掉的声音", "不安"],
                title: "关于「无尽的楼梯」的夜里",
                note: nil,
                isArchived: false,
                comicArtifacts: []
            ),
            Dream(
                id: id5,
                createdAt: d5,
                rawTranscript: "我在睡着的天空里寻找火车站，地面却不停变成水纹。",
                organizedText: "天空像一张被盖住的被单。我找火车站，可脚下的地面不断变成水纹，像把目的地也揉开了。",
                interpretation: "这段梦把“路线感”变成了可流动的东西：你也许正在重新定义，什么叫做到达。",
                tags: ["火车站", "水纹", "寻找", "迷雾"],
                title: "关于「找不到的火车站」的夜里",
                note: nil,
                isArchived: false,
                comicArtifacts: []
            ),
            Dream(
                id: id6,
                createdAt: d6,
                rawTranscript: "我梦见牙齿又回到了嘴里，可它们像在发光，照亮我不敢看的角落。",
                organizedText: "牙齿回到嘴里，亮得像小小的星。它们照亮我不敢看向的角落，仿佛提醒我：有些害怕可以被温柔地照见。",
                interpretation: "发光的牙齿像是把“失去/担心”转成可观察的符号：当你愿意看见，害怕也会松动。",
                tags: ["牙齿", "发光", "照见", "温柔"],
                title: "关于「发光的牙齿」的夜里",
                note: nil,
                isArchived: false,
                comicArtifacts: []
            )
        ]
    }
}

extension DreamStore {
    /// 仅在**当前没有任何梦境**时注入 6 条示例梦（MVP 演示 / 空库体验）。
    /// 使用固定 `Dream.id`，因此多次调用也不会重复插入。
    /// 若用户曾录过梦、列表非空，则不会混入示例，避免污染真实数据。
    func seedDemoDreamsIfNeeded() {
        guard dreams.isEmpty else { return }

        let now = Date()
        let demoDreams = DemoDreams.makeDemoDreams(now: now)
        for dream in demoDreams {
            upsert(dream)
        }
    }
}

