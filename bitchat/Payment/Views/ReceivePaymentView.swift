import SwiftUI
import CoreImage.CIFilterBuiltins

/// View for receiving payments (shows QR code and address)
struct ReceivePaymentView: View {
    let wallet: Wallet?
    @Binding var isPresented: Bool

    @State private var amount: String = ""
    @State private var label: String = ""
    @State private var message: String = ""
    @State private var showCopiedAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let wallet = wallet {
                        // QR Code
                        qrCodeView(for: paymentRequest)

                        // Address
                        addressSection(wallet.identity.address)

                        // Optional payment details
                        paymentDetailsSection

                        // Copy button
                        copyButton
                    } else {
                        Text("No wallet available")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Receive Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Payment address copied to clipboard")
            }
        }
    }

    // MARK: - Subviews

    private func qrCodeView(for request: PaymentRequest?) -> some View {
        VStack {
            if let qrImage = generateQRCode(from: request?.toQRString() ?? wallet?.identity.address ?? "") {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 250, height: 250)
                    .overlay(
                        Text("QR Code Unavailable")
                            .foregroundColor(.secondary)
                    )
            }
        }
    }

    private func addressSection(_ address: String) -> some View {
        VStack(spacing: 8) {
            Text("Payment Address")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(address)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }

    private var paymentDetailsSection: some View {
        VStack(spacing: 16) {
            Divider()

            VStack(spacing: 12) {
                HStack {
                    Text("Amount (Optional)")
                        .font(.subheadline)
                    Spacer()
                    TextField("0.00000000", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("MT")
                        .foregroundColor(.secondary)
                }

                TextField("Label (Optional)", text: $label)

                TextField("Message (Optional)", text: $message)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }

    private var copyButton: some View {
        Button(action: copyAddress) {
            HStack {
                Image(systemName: "doc.on.doc")
                Text("Copy Address")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    // MARK: - Computed Properties

    private var paymentRequest: PaymentRequest? {
        guard let wallet = wallet else { return nil }

        let amountValue = Double(amount) ?? 0
        let amountInUnits = UInt64(amountValue * 100_000_000)

        guard amountInUnits > 0 else { return nil }

        return PaymentRequest(
            address: wallet.identity.address,
            amount: amountInUnits,
            label: label.isEmpty ? nil : label,
            message: message.isEmpty ? nil : message
        )
    }

    // MARK: - Actions

    private func copyAddress() {
        if let address = wallet?.identity.address {
            UIPasteboard.general.string = address
            showCopiedAlert = true
        }
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up the QR code
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
