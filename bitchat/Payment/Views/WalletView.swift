import SwiftUI

/// Main wallet view showing balance and transaction history
struct WalletView: View {
    @ObservedObject var walletManager: WalletManager
    @ObservedObject var paymentService: PaymentService
    @State private var showSendPayment = false
    @State private var showReceivePayment = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Wallet Balance Card
                    balanceCard

                    // Action Buttons
                    actionButtons

                    // Transaction History
                    transactionHistory
                }
                .padding()
            }
            .navigationTitle("MeshPay Wallet")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Create New Wallet") {
                            createNewWallet()
                        }
                        Button("Import Wallet") {
                            // TODO: Show import dialog
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSendPayment) {
                SendPaymentView(
                    walletManager: walletManager,
                    paymentService: paymentService,
                    isPresented: $showSendPayment
                )
            }
            .sheet(isPresented: $showReceivePayment) {
                ReceivePaymentView(
                    wallet: walletManager.currentWallet,
                    isPresented: $showReceivePayment
                )
            }
        }
    }

    // MARK: - Subviews

    private var balanceCard: some View {
        VStack(spacing: 12) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(String(format: "%.8f MT", walletManager.balance.totalTokens))
                .font(.system(size: 36, weight: .bold, design: .rounded))

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Confirmed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.8f MT", walletManager.balance.confirmedTokens))
                        .font(.footnote)
                }

                VStack(alignment: .leading) {
                    Text("Pending")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.8f MT", walletManager.balance.pendingTokens))
                        .font(.footnote)
                }

                VStack(alignment: .leading) {
                    Text("UTXOs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(walletManager.balance.utxoCount)")
                        .font(.footnote)
                }
            }

            if let wallet = walletManager.currentWallet {
                Text(wallet.identity.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: { showSendPayment = true }) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Send")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Button(action: { showReceivePayment = true }) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Receive")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }

    private var transactionHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.horizontal)

            if paymentService.transactionHistory.isEmpty {
                Text("No transactions yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(paymentService.transactionHistory.reversed()) { transaction in
                    TransactionRow(transaction: transaction, currentWallet: walletManager.currentWallet)
                }
            }
        }
    }

    // MARK: - Actions

    private func createNewWallet() {
        do {
            _ = try walletManager.createWallet(label: "Wallet \(walletManager.wallets.count + 1)")
        } catch {
            // Handle error
        }
    }
}

/// Row view for a single transaction
struct TransactionRow: View {
    let transaction: Transaction
    let currentWallet: Wallet?

    private var isReceived: Bool {
        guard let wallet = currentWallet else { return false }
        return transaction.outputs.contains { $0.address == wallet.identity.address }
    }

    private var amount: UInt64 {
        guard let wallet = currentWallet else { return 0 }
        if isReceived {
            return transaction.outputs
                .filter { $0.address == wallet.identity.address }
                .reduce(0) { $0 + $1.amount }
        } else {
            return transaction.totalOutputAmount()
        }
    }

    var body: some View {
        HStack {
            Image(systemName: isReceived ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundColor(isReceived ? .green : .blue)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(isReceived ? "Received" : "Sent")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(transaction.id.prefix(16) + "...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(isReceived ? "+" : "-")\(String(format: "%.8f", Double(amount) / 100_000_000.0)) MT")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(transaction.confirmations) confirmations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
