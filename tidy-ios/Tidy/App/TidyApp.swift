import SwiftUI

@main
struct TidyApp: App {
    @State private var library = PhotoLibrary()
    @State private var decisions = DecisionStore()
    @State private var scanner = SimilarScanner()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(decisions)
                .environment(scanner)
        }
    }
}

struct RootView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.isAuthorized {
                MainTabs()
            } else {
                AccessView()
            }
        }
        .task { await library.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await library.reload() }
            }
        }
    }
}

struct MainTabs: View {
    @Environment(DecisionStore.self) private var decisions

    var body: some View {
        TabView {
            MonthsView()
                .tabItem { Label("Months", systemImage: "calendar") }
            CleanupView()
                .tabItem { Label("Clean Up", systemImage: "sparkles") }
            NavigationStack { BinView() }
                .tabItem { Label("Bin", systemImage: "trash") }
                .badge(decisions.binned.count)
        }
    }
}

struct AccessView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Tidy your camera roll")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Label("Swipe left to bin, right to keep", systemImage: "hand.draw")
                Label("Find similar shots and big videos", systemImage: "square.on.square")
                Label("Everything stays on this phone. Tidy has no internet code, no accounts, no tracking.", systemImage: "lock.shield")
            }
            .font(.body)
            .padding()
            Spacer()
            if library.status == .notDetermined {
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Text("Allow Photo Access").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Photo access is off. Turn it on in Settings to use Tidy.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}
