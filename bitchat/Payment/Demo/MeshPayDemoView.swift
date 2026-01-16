import SwiftUI

/// Interactive demo view for MeshPay v1.1 features
struct MeshPayDemoView: View {
    @StateObject private var demo = MeshPayDemo()
    @State private var isRunning = false
    @State private var selectedScenario: Int = 0

    let scenarios = [
        ("Multi-Currency", "dollarsign.circle.fill", "Test multiple asset types"),
        ("Atomic Swap", "arrow.left.arrow.right.circle.fill", "Cross-currency exchange"),
        ("Hardware Wallet", "lock.shield.fill", "Secure key management"),
        ("Bank Integration", "building.columns.fill", "Fiat funding")
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Scenario Selector
                scenarioSelector

                Divider()

                // Console Output
                consoleOutput

                Divider()

                // Control Buttons
                controlButtons
            }
            .navigationTitle("MeshPay v1.1 Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var scenarioSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Demo Scenario")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(scenarios.enumerated()), id: \.offset) { index, scenario in
                        ScenarioCard(
                            title: scenario.0,
                            icon: scenario.1,
                            description: scenario.2,
                            isSelected: selectedScenario == index
                        )
                        .onTapGesture {
                            selectedScenario = index
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemGroupedBackground))
    }

    private var consoleOutput: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 4) {
                    if demo.scenarioLog.isEmpty {
                        Text("Console output will appear here...")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    } else {
                        ForEach(Array(demo.scenarioLog.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(colorForLogLine(line))
                                .id(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .onChange(of: demo.scenarioLog.count) { _ in
                    if let lastIndex = demo.scenarioLog.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var controlButtons: some View {
        HStack(spacing: 16) {
            Button(action: runSelectedScenario) {
                HStack {
                    Image(systemName: isRunning ? "hourglass" : "play.circle.fill")
                    Text(isRunning ? "Running..." : "Run Demo")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isRunning)

            Button(action: runFullDemo) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Run All")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isRunning)

            Button(action: clearConsole) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                    Text("Clear")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Actions

    private func runSelectedScenario() {
        isRunning = true

        Task {
            switch selectedScenario {
            case 0:
                await demo.runScenario1_MultiCurrencyBasics()
            case 1:
                await demo.runScenario2_AtomicSwap()
            case 2:
                await demo.runScenario3_HardwareWallet()
            case 3:
                await demo.runScenario4_BankIntegration()
            default:
                break
            }

            await MainActor.run {
                isRunning = false
            }
        }
    }

    private func runFullDemo() {
        isRunning = true

        Task {
            await demo.runFullDemo()

            await MainActor.run {
                isRunning = false
            }
        }
    }

    private func clearConsole() {
        demo.reset()
    }

    // MARK: - Helpers

    private func colorForLogLine(_ line: String) -> Color {
        if line.contains("❌") || line.contains("Error") {
            return .red
        } else if line.contains("✅") || line.contains("✓") {
            return .green
        } else if line.contains("⚠️") {
            return .orange
        } else if line.contains("🚀") || line.hasPrefix("##") {
            return .blue
        } else if line.hasPrefix("   ") {
            return .secondary
        } else {
            return .primary
        }
    }
}

/// Scenario card component
struct ScenarioCard: View {
    let title: String
    let icon: String
    let description: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(isSelected ? .white : .blue)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .primary)

            Text(description)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140, height: 120)
        .padding()
        .background(isSelected ? Color.blue : Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: isSelected ? 4 : 2)
    }
}

// MARK: - Preview

struct MeshPayDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MeshPayDemoView()
    }
}
