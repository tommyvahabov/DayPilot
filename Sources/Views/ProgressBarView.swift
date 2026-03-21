import SwiftUI

struct ProgressBarView: View {
    let current: Int
    let capacity: Int

    private var progress: Double {
        guard capacity > 0 else { return 0 }
        return min(Double(current) / Double(capacity), 1.0)
    }

    private var color: Color {
        let ratio = Double(current) / Double(max(capacity, 1))
        if ratio >= 1.0 { return .red }
        if ratio >= 0.8 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))

                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}
