import SwiftUI

/// View for sending payments
struct SendPaymentView: View {
    @ObservedObject var walletManager: WalletManager
    @ObservedObject var paymentService: PaymentService
    @Binding var isPresented: Bool

    @State private var recipientAddress: String = ""
    @State private var amount: String = ""
    @State private var memo: String = ""
    @State private var isSending: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showScanner: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Recipient")) {
                    HStack {
                        TextField("Payment Address", text: $recipientAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button(action: { showScanner = true }) {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }

                    if !recipientAddress.isEmpty && !PaymentIdentity.isValidAddress(recipientAddress) {
                        Text("Invalid address")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Amount")) {
                    HStack {
                        TextField("0.00000000", text: $amount)
                            .keyboardType(.decimalPad)

                        Text("MT")
                            .foregroundColor(.secondary)
                    }

                    Text("Available: \(String(format: "%.8f MT", walletManager.balance.confirmedTokens))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Memo (Optional)")) {
                    TextField("Add a note", text: $memo)
                }

                Section {
                    HStack {
                        Text("Transaction Fee")
                        Spacer()
                        Text("0.00001 MT")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Total")
                            .fontWeight(.bold)
                        Spacer()
                        Text(totalAmount)
                            .fontWeight(.bold)
                    }
                }

                Section {
                    Button(action: sendPayment) {
                        if isSending {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Sending...")
                                    .padding(.leading, 8)
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Send Payment")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(!canSend || isSending)
                }
            }
            .navigationTitle("Send Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView(scannedText: $recipientAddress, isPresented: $showScanner)
            }
        }
    }

    // MARK: - Computed Properties

    private var canSend: Bool {
        guard !recipientAddress.isEmpty,
              PaymentIdentity.isValidAddress(recipientAddress),
              let amountValue = Double(amount),
              amountValue > 0,
              amountValue <= walletManager.balance.confirmedTokens else {
            return false
        }
        return true
    }

    private var totalAmount: String {
        guard let amountValue = Double(amount) else {
            return "0.00000000 MT"
        }
        let total = amountValue + 0.00001 // Add fee
        return String(format: "%.8f MT", total)
    }

    // MARK: - Actions

    private func sendPayment() {
        guard canSend else { return }

        isSending = true

        Task {
            do {
                guard let amountValue = Double(amount) else {
                    throw PaymentError.invalidAddress
                }

                let amountInUnits = UInt64(amountValue * 100_000_000)
                let fee: UInt64 = 1000 // 0.00001 MT

                _ = try await paymentService.sendPayment(
                    to: recipientAddress,
                    amount: amountInUnits,
                    fee: fee,
                    memo: memo.isEmpty ? nil : memo
                )

                await MainActor.run {
                    isSending = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

/// Placeholder QR scanner view
struct QRScannerView: View {
    @Binding var scannedText: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack {
                Text("QR Scanner")
                    .font(.title)

                // TODO: Implement actual QR scanner using AVFoundation
                Text("QR scanning not implemented yet")
                    .foregroundColor(.secondary)
                    .padding()

                Button("Cancel") {
                    isPresented = false
                }
                .padding()
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
