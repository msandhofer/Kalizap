import SwiftUI

struct SpectrumView: View {
    let bands: [Float]
    let barCount: Int
    let height: CGFloat
    let barWidth: CGFloat
    let spacing: CGFloat
    let color: Color

    init(
        bands: [Float],
        barCount: Int = 20,
        height: CGFloat = 22,
        barWidth: CGFloat = 2.5,
        spacing: CGFloat = 3,
        color: Color = Color(red: 0x0A/255.0, green: 0x84/255.0, blue: 0xFF/255.0)
    ) {
        self.bands = bands
        self.barCount = barCount
        self.height = height
        self.barWidth = barWidth
        self.spacing = spacing
        self.color = color
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: barWidth, height: barHeight(at: index))
                    .animation(.easeOut(duration: 0.08), value: bands)
            }
        }
        .frame(height: height)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let minHeight: CGFloat = 3
        let value: Float
        if index < bands.count {
            value = bands[index]
        } else {
            value = 0
        }
        return minHeight + CGFloat(value) * (height - minHeight)
    }
}

#Preview {
    SpectrumView(bands: (0..<20).map { Float($0) / 20 })
        .padding()
        .background(.ultraThinMaterial)
}
