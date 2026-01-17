import SwiftUI

/// View modifier that adds a MeshPay demo launcher button to any view
struct MeshPayDemoButton: View {
    @State private var showingDemo = false

    var body: some View {
        Button(action: {
            showingDemo = true
        }) {
            HStack {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundColor(.orange)
                Text("MeshPay Demo")
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .sheet(isPresented: $showingDemo) {
            NavigationView {
                MeshPayDemoView()
                    .navigationTitle("MeshPay v1.1 Demo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDemo = false
                            }
                        }
                    }
            }
        }
    }
}

// Usage in any view:
// MeshPayDemoButton()
