import SwiftUI
import Charts

/// The member's visits, laid out like Fitness and Health: this week against the goal, then a grid of summary cards,
/// the visits chart, milestones, the class mix and the month. Each section is its own view, so a drag on the chart
/// re-runs only the chart.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    /// Weeks shown by the visits chart and the class mix.
    @State private var range = 12

    var body: some View {
        List {
            if model.visits.isEmpty {
                ContentUnavailableView {
                    Label("Your first visit starts the streak", systemImage: "figure.walk")
                } description: { Text("Check in once and this page fills in.") } actions: {
                    Button("Book a class") { router.selection = .book }.primaryAction()
                }.listRowBackground(Color.clear)
            } else {
                // The streak walks 60 weeks of visits, so it is read once here and passed down.
                let streak = model.streak
                ProgressHero(streak: streak)
                ProgressSummaryGrid()
                VisitsChartSection(range: $range)
                // As on the web, the best streak picks the step and the current streak is the count toward it.
                MilestonesSection(streakWeeks: streak.weeks, bestStreak: model.member.stats == nil ? streak.weeks : streak.best)
                ClassMixSection(weeks: range)
                MonthSection()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Hero

/// This week against the goal on the ribs, the streak and the best streak, the week as a row of days, and the goal.
private struct ProgressHero: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    var streak: StreakInfo

    var body: some View {
        let goal = model.weeklyGoal
        let met = streak.thisWeek >= goal
        let ws = model.weekStart(model.now)
        let today = AZ.cal.dateComponents([.day], from: ws, to: model.now.startOfAZDay).day ?? 0
        let dots: [Bool] = (0..<7).map { i in
            let d = ws.addingDays(i)
            return model.visits.contains { $0 >= d && $0 < d.addingDays(1) && $0 <= model.now }
        }
        let tint = met ? Color.statusSuccess : Color.brandAccent
        Section {
            VStack(alignment: .leading, spacing: 18) {
                (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 20))) {
                    ProgressRibs(value: streak.thisWeek, goal: goal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(streak.thisWeek)").brandFont(.numeral(.hero)).foregroundStyle(tint)
                            Text("of \(goal) visits").font(.headline).foregroundStyle(.secondary)
                        }
                        Text(met ? "Goal met" : "\(goal - streak.thisWeek) more to reach your goal")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Divider()
                // Two labelled values side by side, like the grid on a Fitness workout.
                (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                    HeroValue(label: "Streak", value: "\(streak.weeks)", unit: streak.weeks == 1 ? "week" : "weeks", tint: .statusSuccess)
                    HeroValue(label: "Best streak", value: "\(streak.best)", unit: streak.best == 1 ? "week" : "weeks", tint: .primary)
                }
            }
            .padding(.vertical, 6)
            VisitStreakStrip(weeks: streak.weeks, visited: dots, todayIndex: today, thisWeek: streak.thisWeek, showHeader: false)
                .padding(.vertical, 4)
            Button { router.present(.goal) } label: {
                LabeledContent {
                    Text("\(goal) visits a week")
                } label: {
                    Label("Weekly goal", systemImage: "target")
                }
            }
            .accessibilityHint("Changes your weekly goal")
        }
    }
}

private struct HeroValue: View {
    var label: String
    var value: String
    var unit: String
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).brandFont(.numeral(.large)).foregroundStyle(tint)
                Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Summary grid

/// Four summary cards in two pairs, like the Fitness summary. Each pair stacks at accessibility sizes.
private struct ProgressSummaryGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        let monthStart = AZ.cal.date(from: AZ.cal.dateComponents([.year, .month], from: model.now))!
        let monthVisits = model.visits.filter { $0 >= monthStart && $0 <= model.now }.count
        // The web uses four weeks of the weekly goal as the month goal. The two apps must agree.
        let monthGoal = model.weeklyGoal * 4
        let monthMet = monthVisits >= monthGoal
        let lifetime = model.lifetimeVisits
        let attended = model.bookings.filter { $0.status == .attended }
        let favClass = Dictionary(grouping: attended, by: \.title).max { $0.value.count < $1.value.count }
        let favClub = Dictionary(grouping: attended, by: \.clubID).max { $0.value.count < $1.value.count }

        Section {
            SummaryTileGrid {
                SummaryTilePair {
                    StatCard(title: "This month", symbol: "calendar", tint: Color.linkText, time: nil,
                             value: "\(monthVisits)", unit: "of \(monthGoal) visits",
                             detail: monthMet ? "Goal met" : "\(monthGoal - monthVisits) to go", valueAtTop: true, action: nil) {
                        ProgressView(value: Double(min(monthVisits, monthGoal)), total: Double(monthGoal))
                            .tint(monthMet ? Color.statusSuccess : Color.brandAccent)
                            .accessibilityHidden(true)
                    }
                    StatCard(title: "Lifetime", symbol: "figure.walk", tint: Color.brandSecondary, time: nil,
                             value: "\(lifetime)", unit: lifetime == 1 ? "visit" : "visits",
                             detail: model.member.sinceText.isEmpty ? nil : "Since \(model.member.sinceText)", valueAtTop: true, action: nil)
                }
                SummaryTilePair {
                    // The name is the fact here, so it is the value and the count is the line under it.
                    StatCard(title: "Top class", symbol: "heart.fill", tint: Color.brandAccent, time: nil,
                             value: favClass?.key ?? "None yet", unit: nil,
                             detail: favClass.map { classes($0.value.count) }, valueLines: 2, valueAtTop: true, action: nil)
                    if let favClub {
                        let club = model.club(favClub.key)
                        StatCard(title: "Top club", symbol: "mappin.and.ellipse", tint: Color.statusSuccess, time: nil,
                                 value: club.fullName, unit: nil, detail: classes(favClub.value.count),
                                 valueLines: 2, valueAtTop: true) { router.push(.club(club.id)) }
                    } else {
                        StatCard(title: "Top club", symbol: "mappin.and.ellipse", tint: Color.statusSuccess, time: nil,
                                 value: "None yet", unit: nil, detail: nil, valueLines: 2, valueAtTop: true, action: nil)
                    }
                }
            }
        }
    }
}

private func classes(_ n: Int) -> String { n == 1 ? "1 class" : "\(n) classes" }

// MARK: - Visits chart

/// Visits a week, as Health shows a metric: the range, the average (or the week the member drags to), the dates, the
/// bars against the goal, then a highlight that compares this week with the average.
private struct VisitsChartSection: View {
    @Environment(AppModel.self) private var model
    @Binding var range: Int
    @State private var asTable = false
    /// The week the member drags to on the chart. The headline over the chart shows it.
    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var chartH: CGFloat = 200
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        // Weeks before the first visit are not missed weeks, so the chart starts at the week of the first visit.
        // Every week shown then counts in "Goal met in X of Y", and its bar colour says the same.
        let firstVisit = model.visits.filter { $0 <= model.now }.min() ?? model.now
        let weeks = model.weeklyCounts(range).filter { $0.start >= model.weekStart(firstVisit) }
        let goal = model.weeklyGoal
        let avg = Double(weeks.map(\.count).reduce(0, +)) / Double(max(weeks.count, 1))
        let avgText = avg.formatted(.number.precision(.fractionLength(1)))
        let met = weeks.filter { $0.count >= goal }.count
        let picked = selectedDate.flatMap { d in weeks.first { d >= $0.start && d < $0.start.addingDays(7) } }
        // Room above the tallest bar and the goal, so neither touches the top.
        let yMax = max(weeks.map(\.count).max() ?? 0, goal) + 1
        let first = weeks.first?.start ?? model.now
        let dates = picked.map { span($0.start, min($0.start.addingDays(6), model.now)) } ?? span(first, model.now)
        let thisWeek = weeks.last?.count ?? 0
        // The week is not over, so it is compared with past weeks at the same point: the same time since Monday.
        let elapsed = model.now.timeIntervalSince(model.weekStart(model.now))
        let past = weeks.dropLast()
        let pace: Double? = past.isEmpty ? nil : Double(past.map { w in
            model.visits.filter { $0 >= w.start && $0 < w.start.addingTimeInterval(elapsed) }.count
        }.reduce(0, +)) / Double(past.count)

        Section {
            Picker("Range", selection: $range) { Text("4 weeks").tag(4); Text("12 weeks").tag(12); Text("1 year").tag(52) }
                .pickerStyle(.segmented)
                .onChange(of: range) { selectedDate = nil }
            VStack(alignment: .leading, spacing: 0) {
                Text(picked == nil ? "Average" : "Week")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(picked.map { "\($0.count)" } ?? avgText).brandFont(.numeral(.large))
                    Text(picked == nil ? "visits a week" : (picked!.count == 1 ? "visit" : "visits"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(dates).font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if asTable {
                ForEach(weeks, id: \.start) { w in
                    LabeledContent("Week of \(w.start.cpDayMonth)") {
                        Text("\(w.count)").monospacedDigit().foregroundStyle(w.count >= goal ? Color.statusSuccess : Color.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    chart(weeks, goal: goal, yMax: yMax, picked: picked?.start)
                        .accessibilityChartDescriptor(VisitsDescriptor(
                            weeks: weeks.map { ($0.start.cpDayMonth, $0.count) },
                            summary: "Average \(avgText) visits a week. Goal \(goal) met in \(met) of \(weeks.count) weeks."))
                    (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 16))) {
                        Legend(color: .statusSuccess, text: "Goal met")
                        Legend(color: .brandAccent, text: "Under goal")
                        // The goal is named here, not on the line, where it would sit on top of a bar.
                        HStack(spacing: 5) {
                            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 16, y: 1)) }
                                .stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(width: 16, height: 2)
                            Text("Goal \(goal)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                }
            }
            if let pace {
                Highlight(thisWeek: thisWeek, usual: pace, goal: goal, weekday: model.now.cpFormat("EEEE"))
            }
            Button(asTable ? "View as chart" : "View as table") { asTable.toggle() }
        } header: {
            DetailSectionHeader(title: "Visits", detail: "Goal met in \(met) of \(weeks.count) weeks")
        }
    }

    /// A date range as Health writes it: "Aug 10–Oct 27, 2026", with the year once when both ends share it.
    private func span(_ a: Date, _ b: Date) -> String {
        let sameYear = AZ.cal.component(.year, from: a) == AZ.cal.component(.year, from: b)
        return "\(a.cpFormat(sameYear ? "MMM d" : "MMM d, yyyy"))–\(b.cpFormat("MMM d, yyyy"))"
    }

    private func chart(_ weeks: [(start: Date, count: Int)], goal: Int, yMax: Int, picked: Date?) -> some View {
        let dash = StrokeStyle(lineWidth: 0.5, dash: [2, 3])
        // Large dates need more room each, so accessibility sizes label about three weeks across the range.
        let stride = dts.isAccessibilitySize ? max(weeks.count / 3, 1) : (weeks.count > 12 ? 8 : (weeks.count > 4 ? 2 : 1))
        return Chart {
            ForEach(weeks, id: \.start) { w in
                // A week with no visit gets a short stub, so a missed week shows as a copper mark, not a gap.
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Visits", w.count == 0 ? Double(yMax) * 0.025 : Double(w.count)))
                    .foregroundStyle(w.count >= goal ? Color.statusSuccess : Color.brandAccent)
                    .cornerRadius(3)
                    .opacity(picked == nil || picked == w.start ? 1 : 0.35)
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...yMax)
        // A trailing axis with dashed grid lines, as in Health.
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: dash)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: stride)) { _ in
                AxisGridLine(stroke: dash)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        // Axis text stops growing at the first accessibility size, so the bars keep their room. "View as table"
        // shows the same numbers at full size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Weeks start on Monday in Arizona time, as in the model. Without this the bars and labels use Sunday weeks.
        .environment(\.calendar, AZ.cal)
        .frame(height: min(chartH, 320))
        .padding(.vertical, 8)
    }
}

private struct Legend: View {
    var color: Color
    var text: String
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// This week so far against the usual count by the same point of a week, as two bars, like a Health highlight.
/// A week that met the goal never gets a "behind" line.
private struct Highlight: View {
    var thisWeek: Int
    /// The average visits in past weeks by the same time since Monday.
    var usual: Double
    var goal: Int
    var weekday: String

    var body: some View {
        let top = max(Double(thisWeek), usual, 1)
        let usualText = usual.formatted(.number.precision(.fractionLength(1)))
        // Compare at the precision shown, so 3 against "3.0" reads as the same.
        let diff = (Double(thisWeek) - usual).rounded(toPlaces: 1)
        let met = thisWeek >= goal
        let line = met
            ? (diff > 0 ? "You met your goal and are ahead of your usual pace." : "You met your goal this week.")
            : (diff > 0 ? "You are ahead of your usual pace this week."
               : (diff == 0 ? "You are on your usual pace this week." : "You are behind your usual pace this week."))
        let symbol = met ? "checkmark.circle" : (diff > 0 ? "arrow.up.right" : (diff == 0 ? "equal" : "arrow.down.right"))
        VStack(alignment: .leading, spacing: 10) {
            Label("Highlight", systemImage: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.linkText)
            Text(line)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            bar("This week so far", "\(thisWeek)", Double(thisWeek) / top, met ? Color.statusSuccess : Color.brandAccent)
            bar("Usual by \(weekday)", usualText, usual / top, Color(.systemGray3))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Highlight. \(line) \(thisWeek) visits this week so far. Usually \(usualText) by \(weekday).")
    }

    private func bar(_ label: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).brandFont(.numeral(.small))
                Text("visits").font(.footnote).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                Capsule().fill(color).frame(width: max(8, g.size.width * fraction))
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Milestones

/// One milestone: what it counts, the target, and how far along it is. Built only from the member's own data.
private struct Milestone: Identifiable {
    var name: String
    var symbol: String
    var value: Int
    var target: Int
    var unit: String
    var id: String { name }
    var done: Bool { value >= target }
}

/// Milestones in progress as a grid, like "Go For It" in Fitness, then the ones reached as a compact "Earned" row,
/// as Fitness keeps earned awards apart. The grid shows the next step of each kind.
private struct MilestonesSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dts
    var streakWeeks: Int
    /// Picks the streak steps that are earned. Without a backend it is the current streak, because the model gives
    /// the best streak a floor there.
    var bestStreak: Int

    private var milestones: [Milestone] {
        let visits = model.lifetimeVisits
        let attended = model.bookings.filter { $0.status == .attended }
        let clubs = Set(attended.map(\.clubID)).count
        // Every reached step, and the next step, of one kind.
        // `reached` decides which steps are earned; `value` is the count shown toward the next one.
        func steps(_ tiers: [Int], value: Int, reached: Int? = nil, name: (Int) -> String, symbol: String, unit: String) -> [Milestone] {
            let r = reached ?? value
            let shown = tiers.filter { $0 <= r } + [tiers.first { $0 > r }].compactMap { $0 }
            return shown.map { Milestone(name: name($0), symbol: symbol, value: $0 <= r ? $0 : value, target: $0, unit: unit) }
        }
        // The same steps as the web (`MILESTONES` in lib/insights.ts, `STREAK_STEPS` in lib/progress.ts).
        var all = steps([10, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000], value: visits, name: { "\($0) visits" }, symbol: "figure.walk", unit: "visits")
        all += steps([10, 25, 50, 100, 250], value: attended.count, name: { "\($0) classes" }, symbol: "figure.strengthtraining.traditional", unit: "classes")
        all += steps([4, 8, 12, 16, 26, 52], value: streakWeeks, reached: max(bestStreak, streakWeeks), name: { "\($0)-week streak" }, symbol: "leaf.fill", unit: "weeks")
        if model.clubs.count > 1 {
            all.append(Milestone(name: "Every club", symbol: "mappin.and.ellipse", value: clubs, target: model.clubs.count, unit: "clubs"))
        }
        return all
    }

    var body: some View {
        let all = milestones
        // Nearest to done first.
        let open = all.filter { !$0.done }.sorted { Double($0.value) / Double($0.target) > Double($1.value) / Double($1.target) }
        let earned = all.filter(\.done)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: dts.isAccessibilitySize ? 1 : 2)
        Section {
            if !open.isEmpty {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 20) {
                    ForEach(open) { MilestoneCell(milestone: $0) }
                }
                .padding(.vertical, 8)
            }
            if !earned.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Earned").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    FlowLayout(spacing: 8) {
                        ForEach(earned) { EarnedChip(name: $0.name) }
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            DetailSectionHeader(title: "Milestones")
        }
    }
}

/// A reached milestone: a check badge and the name in a capsule.
private struct EarnedChip: View {
    var name: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.statusSuccess).accessibilityHidden(true)
            Text(name).foregroundStyle(Color.primary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.statusSuccessSubtle, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), earned")
    }
}

private struct MilestoneCell: View {
    var milestone: Milestone
    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 44

    var body: some View {
        let m = milestone
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle().fill(Color(.tertiarySystemFill))
                Image(systemName: m.symbol)
                    .font(.body.weight(.bold))
                    // The circle stops growing at 64 pt, so the glyph stops growing with it.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Color.primary)
            }
            .frame(width: min(badge, 64), height: min(badge, 64))
            .accessibilityHidden(true)
            Text(m.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("\(m.value) of \(m.target) \(m.unit)")
                .font(.footnote).monospacedDigit()
                .foregroundStyle(Color.secondary)
            ProgressView(value: Double(min(m.value, m.target)), total: Double(m.target))
                .tint(Color.brandAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.name), \(m.value) of \(m.target) \(m.unit)")
    }
}

// MARK: - Class mix

/// The classes attended in the chart's range, as a donut with the total in the centre, then one row for each kind.
private struct ClassMixSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dts
    var weeks: Int
    /// The donut's height. 170 pt at the default size, so it does not fill the card.
    @ScaledMetric(relativeTo: .body) private var donut: CGFloat = 170
    /// One width for every category glyph, so the names and the row separators line up.
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 30

    var body: some View {
        let data = model.attendedByCategory(weeks: weeks)
        let total = data.map(\.1).reduce(0, +)
        Section {
            if data.isEmpty {
                Text("Classes you attend show here.").foregroundStyle(.secondary)
            } else {
                Chart(data, id: \.0) { c in
                    SectorMark(angle: .value("Classes", c.1), innerRadius: .ratio(0.64), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(c.0.color)
                }
                .chartBackground { proxy in
                    GeometryReader { g in
                        if let plot = proxy.plotFrame {
                            let f = g[plot]
                            VStack(spacing: 0) {
                                Text("\(total)").brandFont(.numeral(.hero))
                                Text(total == 1 ? "class" : "classes").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            // The hole does not grow with the text, so the total stops growing first.
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .position(x: f.midX, y: f.midY)
                        }
                    }
                }
                .frame(width: min(donut, 220), height: min(donut, 220))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityChartDescriptor(VisitsDescriptor(
                    weeks: data.map { ($0.0.title, $0.1) }, summary: "\(total) classes attended in the last \(weeks) weeks.",
                    title: "Classes by kind", xTitle: "Kind", seriesName: "Classes attended"))
                ForEach(data, id: \.0) { c in
                    let share = (Double(c.1) / Double(max(total, 1))).formatted(.percent.precision(.fractionLength(0)))
                    // At accessibility sizes the count and share go under the name, so the name keeps the width.
                    (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
                        HStack(spacing: 12) {
                            Image(systemName: c.0.symbol)
                                .font(.body.weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                                .foregroundStyle(c.0.textColor)
                                .frame(width: min(glyph, 48))
                                .accessibilityHidden(true)
                            Text(c.0.title)
                        }
                        if !dts.isAccessibilitySize { Spacer(minLength: 8) }
                        HStack(spacing: 12) {
                            Text("\(c.1)").monospacedDigit().font(.body.weight(.semibold))
                            Text(share).monospacedDigit().foregroundStyle(.secondary)
                                .frame(minWidth: dts.isAccessibilitySize ? nil : 44, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            DetailSectionHeader(title: "Class mix", detail: weeks == 52 ? "Last year" : "Last \(weeks) weeks")
        }
    }
}

// MARK: - Month

private struct MonthSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let visitDays = Set(model.visits.filter { $0 <= model.now }.map(\.cpDayKey))
        let classDays = Set(model.bookings.filter { $0.status == .attended }.map { $0.start.cpDayKey })
        Section { VisitMonthGrid(month: model.now, visitDays: visitDays, classDays: classDays).padding(.vertical, 4) }
    }
}

// MARK: - Chart descriptor

/// The audio graph for a bar or sector chart of counts by category.
struct VisitsDescriptor: AXChartDescriptorRepresentable {
    var weeks: [(String, Int)]
    var summary: String
    var title = "Visits per week"
    var xTitle = "Week starting"
    var seriesName = "Visits per week"
    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: weeks.map(\.0))
        let maxV = Double(max(weeks.map(\.1).max() ?? 1, 1))
        let y = AXNumericDataAxisDescriptor(title: "Count", range: 0...maxV, gridlinePositions: []) { String(format: "%.0f", $0) }
        let series = AXDataSeriesDescriptor(name: seriesName, isContinuous: false, dataPoints: weeks.map { AXDataPoint(x: $0.0, y: Double($0.1)) })
        return AXChartDescriptor(title: title, summary: summary, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10, Double(p)); return (self * m).rounded() / m }
}
