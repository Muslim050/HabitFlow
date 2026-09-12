import SwiftUI

/// The ring used in rows, the detail header and the widget.
public struct ProgressRing<Label: View>: View {
    public var ratio: Double
    public var color: Color
    public var lineWidth: CGFloat
    public var completed: Bool
    private let label: () -> Label

    public init(ratio: Double, color: Color, lineWidth: CGFloat = 5, completed: Bool = false, @ViewBuilder label: @escaping () -> Label) {
        self.ratio = ratio
        self.color = color
        self.lineWidth = lineWidth
        self.completed = completed
        self.label = label
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: completed ? 1 : min(max(ratio, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.45), value: ratio)
                .animation(.easeOut(duration: 0.45), value: completed)
            label()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(completed ? "Completed" : "\(Int((ratio * 100).rounded())) percent")
    }
}

public extension ProgressRing where Label == EmptyView {
    init(ratio: Double, color: Color, lineWidth: CGFloat = 5, completed: Bool = false) {
        self.init(ratio: ratio, color: color, lineWidth: lineWidth, completed: completed) { EmptyView() }
    }
}
