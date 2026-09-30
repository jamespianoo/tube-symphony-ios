import SwiftUI

/// The website's settings drawer (css/skin-mac/drawer.css, final cascade): a coral
/// header with the wordmark in white and SETTINGS & CONTROLS in ink under it; the
/// desktop grey behind light windows, 12 pt in from the edges and 12 apart; a
/// footer with Reset To Defaults and the credit.
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var showAbout = false
    @State private var showCredits = false

    var body: some View {
        @Bindable var settings = model.settings
        VStack(spacing: 0) {
            // .settings-drawer-header
            HStack {
                MacTitle(title: "Tube Symphony", subtitle: "Settings & Controls", subtitleColor: Mac.cardInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Mac.coral.ignoresSafeArea(edges: .top))
            .overlay(alignment: .bottom) { Rectangle().fill(Mac.cardInk).frame(height: 1) }

            ScrollView {
                VStack(spacing: 12) {
                    MacCard(heading: "Settings") {
                        VStack(spacing: 12) {
                            Toggle(isOn: $settings.showStationNames) { rowLabel("Station names") }
                            Toggle(isOn: $settings.showBlips) { rowLabel("Blips when a note plays") }
                            Toggle(isOn: $settings.smoothMotion) {
                                rowLabel("Smoother motion", note: "Draws trains at 30 fps. Uses more battery and runs warmer.")
                            }
                            Toggle(isOn: $settings.showDiagnostics) { rowLabel("Clock diagnostics") }
                        }
                        .toggleStyle(MacSwitchStyle())
                    }

                    MacCard(heading: "Tube Symphony") {
                        VStack(spacing: 12) {
                            ForEach(Links.tubeSymphony) { LinkRow(item: $0) }
                            DrawerButton(title: "About", systemImage: "info.circle") { showAbout = true }
                        }
                    }

                    MacCard(heading: "More Projects") {
                        VStack(spacing: 12) { ForEach(Links.labs) { LinkRow(item: $0) } }
                    }

                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                        .macType(.drawerCredit).foregroundStyle(Mac.creditGrey)
                }
                .padding(12)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            // .settings-drawer-footer: padding 12 16 16, gap 10, a 1 px ink rule
            VStack(spacing: 10) {
                Button { settings.reset() } label: {
                    Text("Reset To Defaults").macType(.drawerRow).frame(maxWidth: .infinity)
                }
                .buttonStyle(.mac(.light, minHeight: 38))
                DrawerCredit { showCredits = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .overlay(alignment: .top) { Rectangle().fill(Mac.cardInk).frame(height: 1) }
        }
        .background(Mac.desktop.ignoresSafeArea())
        .fullScreenCover(isPresented: $showAbout) { AboutModal() }
        .fullScreenCover(isPresented: $showCredits) { CreditsModal() }
    }

    private func rowLabel(_ title: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).macType(.drawerRow).foregroundStyle(Mac.cardInk)
            if let note { Text(note).macType(.drawerNote).foregroundStyle(Mac.cardDim).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// .settings-drawer-credit: "Created by James Beckwith © 2026 · [Credits]",
/// Johnston 12 / 1.35, .02em, #c9ccd2, the name coral, Credits a small button.
private struct DrawerCredit: View {
    let showCredits: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            Text("Created by ").foregroundStyle(Mac.creditGrey)
            Button("James Beckwith") { openURL(URL(string: "https://www.jamesbeckwith.com")!) }
                .buttonStyle(.plain).foregroundStyle(Mac.coral)
            Text(" © 2026").foregroundStyle(Mac.creditGrey)
            Text("·").foregroundStyle(Mac.creditGrey).padding(.horizontal, 12 * 0.35)
            // .settings-credit-link: Chicago 12, padding 3 8, a 1 px shadow
            Button(action: showCredits) { Text("Credits").macType(.creditLink).padding(.vertical, 3) }
                .buttonStyle(.mac(.light, minHeight: 0, padding: 8, lift: 1))
        }
        .macType(.drawerCredit)
        .frame(maxWidth: .infinity)
    }
}

/// A drawer button (.settings-drawer .settings-link-btn): the light button, the
/// full width of its card, 38 tall, padding 0 12, a 22 pt icon and 12 pt gap,
/// the label in Johnston 14.
struct DrawerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 17)).frame(width: 22, height: 22)
                Text(title).macType(.drawerRow)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.mac(.light, minHeight: 38))
        .padding(.trailing, 2)                                              // width: calc(100% - 2px)
    }
}

struct LinkRow: View {
    let item: LinkItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        DrawerButton(title: item.title, systemImage: item.systemImage) { openURL(item.url) }
    }
}
