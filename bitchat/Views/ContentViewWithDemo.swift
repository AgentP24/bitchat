import SwiftUI

/// Wrapper view that adds MeshPay demo as a tab in the main app
struct ContentViewWithDemo: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Original chat interface
            ContentView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            // MeshPay Demo
            MeshPayDemoView()
                .tabItem {
                    Label("MeshPay Demo", systemImage: "bitcoinsign.circle")
                }
                .tag(1)
        }
    }
}
