import SwiftUI

/// ルート画面。生体認証で解錠するまではロック画面を表示する。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if appState.isUnlocked {
                BcartWebView()
                    .ignoresSafeArea()
            } else {
                LockView()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // バックグラウンドへ移動したら再ロック(復帰時に再度Face IDを要求)
            if newPhase == .background {
                appState.isUnlocked = false
            }
        }
    }
}

/// ロック画面。Face ID / Touch ID で解錠する。
struct LockView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("KEMASHOP")
                .font(.title2.bold())
            Button {
                unlock()
            } label: {
                Label("Face ID で解錠", systemImage: "faceid")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        BiometricGate.authenticate { success in
            if success { appState.isUnlocked = true }
        }
    }
}
