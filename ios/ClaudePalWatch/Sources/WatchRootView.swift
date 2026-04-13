import SwiftUI

struct WatchRootView: View {
    @ObservedObject var controller: WatchConnectivityController

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "cloud.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("ClaudePal")
                    .font(.headline)

                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("ClaudePal")
        }
    }
}
