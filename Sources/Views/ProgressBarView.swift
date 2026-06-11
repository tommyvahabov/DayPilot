import SwiftUI

struct ProgressBarView: View {
    let current: Int
    let capacity: Int

    private var progress: Double {
        guard capacity > 0 else { return 0 }
        return min(Double(current) / Double(capacity), 1.0)
    }

    // Completion semantics: finishing the day is a win, not an overload —
    // green throughout (the old palette went red at 100%).
    private var color: Color {
        progress >= 1.0 ? .green : .green.opacity(0.9)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}
