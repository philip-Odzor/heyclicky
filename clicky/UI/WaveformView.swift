import SwiftUI

/// Animated audio waveform driven by the rolling level buffer in ``AppState``.
struct WaveformView: View {
    let levels: [Float]
    var color: Color = .white
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(
                            width: barWidth,
                            height: max(barWidth, CGFloat(level) * geo.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.12), value: levels)
        }
    }
}

#Preview {
    WaveformView(levels: (0..<28).map { _ in Float.random(in: 0.1...1) }, color: .black)
        .frame(width: 120, height: 28)
        .padding()
}
