import SwiftUI

struct LinesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.lineStatus
        MacPage {
            MacWindow(title: "Line Status", subtitle: "Live from TfL") {
                VStack(alignment: .leading, spacing: 0) {
                    if let err = store.error {
                        Text(err).macType(.hero)
                            .foregroundStyle(Mac.dim)
                            .padding(.vertical, 10)
                    }
                    ForEach(Array((model.data?.lines ?? []).enumerated()), id: \.element.id) { i, line in
                        LineRow(line: line, status: store.statuses[line.key], loaded: store.updated != nil)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Mac.hair).frame(height: 1) } }
                    }
                    if let when = store.updated {
                        Text("Updated \(when.formatted(date: .omitted, time: .shortened)) · \(store.source)")
                            .macType(.clockLabel)
                            .foregroundStyle(Mac.dim)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Mac.hair).frame(height: 1) }
                    }
                }
                .padding(.vertical, -8)   // the rows carry their own 10 pt
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
    }
}

private struct LineRow: View {
    let line: LineInfo
    let status: LineStatusStore.Status?
    let loaded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color(uiColor: UIColor(hex: line.color)))
                .frame(width: 8, height: 34)
                .overlay(Rectangle().strokeBorder(Mac.ink.opacity(0.8), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.name).macType(.body).foregroundStyle(Mac.ink)
                    Spacer(minLength: 4)
                    badge
                }
                if let s = status, !s.isGood, !s.reason.isEmpty {
                    Text(s.reason).macType(.credit).foregroundStyle(Mac.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badge: some View {
        if let s = status {
            Text(s.desc.isEmpty ? "—" : s.desc)
                .macType(.tooltip)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(s.isGood ? Mac.on : (s.severity <= 6 ? Mac.heat : Mac.coral))
                .macEdge(lift: 1)
        } else {
            Text(loaded ? "No status" : "Loading…").macType(.clockLabel).foregroundStyle(Mac.dim)
        }
    }
}
