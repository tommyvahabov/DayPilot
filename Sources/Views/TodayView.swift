import SwiftUI

struct TodayView: View {
    @Bindable var store: ScheduleStore

    // The flip is delightful exactly once — replaying it on every tab switch got old.
    private static var greetingShownThisLaunch = false

    @State private var greeting: Greeting = Greeting.pick()
    @State private var showGreeting: Bool = !TodayView.greetingShownThisLaunch
    @State private var showPostflight = false

    private var today: Date { Date() }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)

            contextCards
                .padding(.horizontal, 24)

            BoardView(store: store)
                .padding(.horizontal, 24)

            bottomBar
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .sheet(isPresented: $showPostflight) {
            PostflightView(store: store)
        }
        .task(id: store.lastGoAround) {
            guard store.lastGoAround != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            store.lastGoAround = nil
        }
    }

    @ViewBuilder
    private var contextCards: some View {
        VStack(spacing: 10) {
            PreflightCardView(store: store)
            BriefingCardView(store: store, collapsible: true)
            ProposalsView(store: store)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .leading) {
            greetingHeader
                .offset(y: showGreeting ? 0 : -78)
                .rotation3DEffect(.degrees(showGreeting ? 0 : 70), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
                .opacity(showGreeting ? 1 : 0)

            dateHeader
                .offset(y: showGreeting ? 78 : 0)
                .rotation3DEffect(.degrees(showGreeting ? -70 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                .opacity(showGreeting ? 0 : 1)
        }
        .frame(height: 64, alignment: .topLeading)
        .clipped()
        .onAppear {
            guard showGreeting else { return }
            Self.greetingShownThisLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.timingCurve(0.65, 0.05, 0.36, 1, duration: 0.7)) {
                    showGreeting = false
                }
            }
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(greeting.emoji).font(.system(size: 13))
                Text(greeting.label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
            }
            Text(greeting.headline)
                .font(.system(size: 25, weight: .bold))
            Text(progressLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
                Text(Self.dayFormatter.string(from: today))
                    .font(.system(size: 25, weight: .bold))
                Text(progressLine)
                    .font(.system(size: 12))
                    .foregroundStyle(store.cautionActive ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
            Spacer()
            closeDayControl
        }
    }

    @ViewBuilder
    private var closeDayControl: some View {
        if store.dayClosedToday {
            Label("Flight closed", systemImage: "airplane.arrival")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        } else {
            Button { showPostflight = true } label: {
                Label("Close the day", systemImage: "airplane.arrival")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            AddTaskView(store: store, compact: false)

            if let s = store.lastGoAround {
                Text("\(s.kept) kept · \(s.diverted) diverted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .transition(.opacity)
            }

            Button { store.goAround() } label: {
                Label("Go-Around", systemImage: "arrow.uturn.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Repack what's left of today from now; divert the rest to tomorrow (⌃⌥G)")
        }
    }

    private var progressLine: String {
        let done = store.completedTodayCount
        let total = store.totalTodayCount
        if total == 0 { return "No tasks scheduled. Add one to get rolling." }
        if done == total { return "All clear. Day's done." }
        if store.cautionActive {
            return "\(done) of \(total) shipped · wheels down \(Self.eta.string(from: store.wheelsDownDate)) — over capacity"
        }
        return "\(done) of \(total) shipped · \(DurationParser.format(minutes: store.queue.todayEffort)) of work left"
    }

    private static let eta: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()
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
