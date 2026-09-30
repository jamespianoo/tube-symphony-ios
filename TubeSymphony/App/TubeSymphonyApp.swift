import SwiftUI

@main
struct TubeSymphonyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Mac.coral)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.sceneBecameActive()
            case .background: model.sceneWentToBackground()
            default: break
            }
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case map, listen, watch, lines, more
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .map: "map"
        case .listen: "headphones"
        case .watch: "play.tv"
        case .lines: "tram"
        case .more: "ellipsis"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // The system tab bar is hidden and the mac one drawn in its place; the
        // TabView still keeps each tab alive and drives the map's appear/disappear.
        VStack(spacing: 0) {
            TabView(selection: $model.tab) {
                MapScreen().tag(AppTab.map).toolbar(.hidden, for: .tabBar)
                ListenView().tag(AppTab.listen).toolbar(.hidden, for: .tabBar)
                WatchView().tag(AppTab.watch).toolbar(.hidden, for: .tabBar)
                LinesView().tag(AppTab.lines).toolbar(.hidden, for: .tabBar)
                MoreView().tag(AppTab.more).toolbar(.hidden, for: .tabBar)
            }
            MacTabBar(selection: $model.tab)
        }
        .background(Mac.desk.ignoresSafeArea())
    }
}

/// The tab bar as a row of mac buttons on the desk: the chosen one is green.
struct MacTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage).font(.system(size: 18, weight: .semibold)).frame(height: 22)
                        Text(tab.title).macType(.navLabel).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mac(on: selection == tab, minHeight: 50, padding: 2))
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            Mac.desk
                .overlay(alignment: .top) { Rectangle().fill(Mac.ink).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
