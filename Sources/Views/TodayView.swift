import SwiftUI

struct TodayView: View {
    @Bindable var store: ScheduleStore

    @State private var greeting: Greeting = Greeting.pick()
    @State private var showGreeting: Bool = true

    private var today: Date { Date() }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var minutesLeft: Int {
        store.queue.today.reduce(0) { $0 + $1.effortMinutes }
    }

    private var minutesDone: Int {
        store.queue.completedToday.reduce(0) { $0 + $1.effortMinutes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                SectionCardView(
                    title: "Today",
                    icon: "sun.max.fill",
                    accent: .green,
                    items: $store.queue.today,
                    store: store,
                    subtitle: subtitle,
                    emptyText: "Runway is clear — nothing left for today",
                    maxHeight: nil
                )

                if !store.queue.completedToday.isEmpty {
                    SectionCardView(
                        title: "Done today",
                        icon: "checkmark.seal.fill",
                        accent: .secondary,
                        items: $store.queue.completedToday,
                        store: store,
                        subtitle: "\(store.queue.completedToday.count) shipped  •  \(formatMinutes(minutesDone)) logged",
                        emptyText: "Nothing shipped yet",
                        maxHeight: nil
                    )
                    .opacity(0.85)
                }
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.background)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            greetingHeader
                .offset(y: showGreeting ? 0 : -78)
                .rotation3DEffect(
                    .degrees(showGreeting ? 0 : 70),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.5
                )
                .opacity(showGreeting ? 1 : 0)

            dateHeader
                .offset(y: showGreeting ? 78 : 0)
                .rotation3DEffect(
                    .degrees(showGreeting ? -70 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.5
                )
                .opacity(showGreeting ? 0 : 1)
        }
        .frame(height: 78, alignment: .topLeading)
        .clipped()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.timingCurve(0.65, 0.05, 0.36, 1, duration: 0.7)) {
                    showGreeting = false
                }
            }
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(greeting.emoji)
                    .font(.system(size: 14))
                Text(greeting.label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
            }
            Text(greeting.headline)
                .font(.system(size: 28, weight: .bold))
            Text(progressLine)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.tertiary)
            Text(Self.dayFormatter.string(from: today))
                .font(.system(size: 28, weight: .bold))
            Text(progressLine)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        "\(store.completedTodayCount)/\(store.totalTodayCount) done  •  \(formatMinutes(minutesLeft)) left"
    }

    private var progressLine: String {
        let done = store.completedTodayCount
        let total = store.totalTodayCount
        if total == 0 { return "No tasks scheduled. Add one to get rolling." }
        if done == total { return "All clear. Day's done." }
        return "\(done) of \(total) shipped  •  \(formatMinutes(minutesLeft)) of work left"
    }

    private func formatMinutes(_ m: Int) -> String {
        if m == 0 { return "0m" }
        let h = m / 60
        let mm = m % 60
        if h == 0 { return "\(mm)m" }
        if mm == 0 { return "\(h)h" }
        return "\(h)h \(mm)m"
    }
}

struct Greeting {
    let label: String      // small caps label
    let headline: String   // big greeting line
    let emoji: String

    static func pick(at date: Date = Date()) -> Greeting {
        let hour = Calendar.current.component(.hour, from: date)
        let pool: [Greeting]

        switch hour {
        case 0..<4:
            pool = [
                Greeting(label: "STILL UP",     headline: "Still grinding, founder?", emoji: "🌙"),
                Greeting(label: "LATE NIGHT",   headline: "Sleep is a strategy.",     emoji: "🌑"),
                Greeting(label: "AFTER HOURS",  headline: "Most quit hours ago.",     emoji: "🕯️"),
                Greeting(label: "GHOST SHIFT",  headline: "It's tomorrow already.",   emoji: "👻"),
            ]
        case 4..<6:
            pool = [
                Greeting(label: "EARLY BIRD",   headline: "Up before the sun.",       emoji: "🌅"),
                Greeting(label: "PRE-DAWN",     headline: "First mover, founder.",    emoji: "☕"),
            ]
        case 6..<12:
            pool = [
                Greeting(label: "MORNING",      headline: "Good morning, founder.",   emoji: "☀️"),
                Greeting(label: "MORNING",      headline: "Up and shipping.",         emoji: "🚀"),
                Greeting(label: "MORNING",      headline: "Coffee's on. Let's move.", emoji: "☕"),
                Greeting(label: "MORNING",      headline: "Make it a day, founder.",  emoji: "✈️"),
            ]
        case 12..<17:
            pool = [
                Greeting(label: "AFTERNOON",    headline: "Good afternoon, founder.", emoji: "🌤️"),
                Greeting(label: "AFTERNOON",    headline: "Halfway through. Keep going.", emoji: "🛫"),
                Greeting(label: "AFTERNOON",    headline: "Still daylight to ship.",  emoji: "🌞"),
            ]
        case 17..<21:
            pool = [
                Greeting(label: "EVENING",      headline: "Good evening, founder.",   emoji: "🌆"),
                Greeting(label: "EVENING",      headline: "Wrap mode, founder.",      emoji: "🛬"),
                Greeting(label: "EVENING",      headline: "Closing the day strong.",  emoji: "🌇"),
            ]
        default: // 21..<24
            pool = [
                Greeting(label: "LATE",         headline: "One more push, founder?",  emoji: "🌙"),
                Greeting(label: "LATE",         headline: "Late shift, captain.",     emoji: "🌒"),
                Greeting(label: "LATE",         headline: "Day's almost wheels-up.",  emoji: "🛩️"),
            ]
        }

        return pool.randomElement() ?? pool[0]
    }
}
