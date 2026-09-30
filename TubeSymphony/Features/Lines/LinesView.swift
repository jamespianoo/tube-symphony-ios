import SwiftUI

struct LinesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.lineStatus
        NavigationStack {
            List {
                if let err = store.error {
                    Label(err, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                }
                ForEach(model.data?.lines ?? []) { line in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(uiColor: UIColor(hex: line.color)))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(line.key == "northern" ? 0.8 : 0), lineWidth: 1))
                            .frame(width: 8, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name).font(.body.weight(.semibold))
                            if let s = store.statuses[line.key] {
                                Text(s.desc.isEmpty ? "—" : s.desc)
                                    .font(.subheadline)
                                    .foregroundStyle(s.isGood ? Color.secondary : Color.orange)
                                if !s.reason.isEmpty {
                                    Text(s.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(store.updated == nil ? "Loading…" : "No status").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if let when = store.updated {
                    Text("Updated \(when.formatted(date: .omitted, time: .shortened)) · from TfL")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lines")
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }
}
