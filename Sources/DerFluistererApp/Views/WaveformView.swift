import SwiftUI
import DerFluisterer

struct WaveformView: View {
    let levels: [Float]
    let barCount: Int

    init(levels: [Float], barCount: Int = 20) {
        self.levels = levels
        self.barCount = barCount
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.primary)
                    .frame(width: 3, height: barHeight(at: index))
            }
        }
        .frame(height: 20)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let level: Float
        if index < levels.count {
            level = levels[index]
        } else {
            level = 0
        }
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 20
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }
}
