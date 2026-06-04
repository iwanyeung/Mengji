import SwiftUI

/// 流式标签布局（iOS 16+ Layout），按子视图 intrinsic 宽度换行，避免 HStack 挤压导致文字竖排。
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8
    /// 为 `nil` 时不限制行数。
    var maxRows: Int? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        flowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowResult(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
        let hiddenProposal = ProposedViewSize(width: 0, height: 0)
        for index in result.positions.count..<subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                proposal: hiddenProposal
            )
        }
    }

    private struct FlowResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero
    }

    private func flowResult(in maxWidth: CGFloat, subviews: Subviews) -> FlowResult {
        var result = FlowResult()
        guard maxWidth > 0, !subviews.isEmpty else { return result }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        var maxX: CGFloat = 0
        var rowIndex = 0

        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxWidth {
                rowIndex += 1
                if let maxRows, rowIndex >= maxRows {
                    break
                }
                y += lineH + spacing
                x = 0
                lineH = 0
            }
            result.positions.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            maxX = max(maxX, x - spacing)
        }

        result.size = CGSize(width: maxX, height: y + lineH)
        return result
    }
}
