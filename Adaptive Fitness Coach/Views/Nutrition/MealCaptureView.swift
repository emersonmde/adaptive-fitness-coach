import SwiftUI
import VisionKit
import Vision
import AdaptiveCore

/// The capture screen (spec §4.1) — a full-screen camera, not a sheet. VisionKit's
/// `DataScannerViewController` runs live barcode + text recognition:
/// - a recognized **barcode auto-advances** with no shutter tap (the fastest salad benchmark),
/// - the **shutter** (the screen's one dominant element) captures a still → Vision OCR →
///   receipt/label/plate classification downstream.
/// Cancel always exits (principle 13). Under `-simulateMealScan` the camera is replaced by
/// `SimulatedCapturePicker` — the simulator has no camera.
struct MealCaptureView: View {
    let onCapture: (MealCapture) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var cancelled = false
    @State private var cameraFailed = false
    @State private var showingTypedEntry = false
    /// The captured frame, frozen on screen while OCR runs — a shutter tap with zero
    /// feedback reads as a miss and invites a second tap.
    @State private var frozenStill: UIImage?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if MealPipelineProvider.isSimulated {
                SimulatedCapturePicker(onCapture: forward)
            } else if cameraFailed {
                cameraUnavailable
            } else {
                scanner
            }
            // Cancel floats top-leading over whatever is showing — always an exit; the typed
            // pill floats bottom (a reserved slot under the shutter, build 8).
            VStack {
                HStack {
                    Button {
                        // A still may be mid-OCR — Cancel must also cancel ITS forward, or
                        // the confirmation sheet pops up over the screen the user returned to.
                        cancelled = true
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityIdentifier("meal.capture.cancel")
                    Spacer()
                }
                Spacer()
                Button {
                    showingTypedEntry = true
                } label: {
                    Label("Type it instead", systemImage: "keyboard")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("meal.capture.typeInstead")
                // Clears the UIKit shutter (64pt, anchored -24 from the safe area) — both
                // used to claim bottom-center and collided.
                .padding(.bottom, MealPipelineProvider.isSimulated ? 4 : 100)
            }
            .padding(16)

            // Frozen frame + progress while OCR runs (the shutter's honest "got it").
            if let frozenStill {
                Image(uiImage: frozenStill)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.accent)
                    Text("Reading…")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $showingTypedEntry) {
            TypedEntryView { capture in
                forward(capture)
            }
        }
    }

    private func forward(_ capture: MealCapture) {
        guard !isCapturing, !cancelled else { return }
        isCapturing = true
        onCapture(capture)
        dismiss()
    }

    private var scanner: some View {
        DataScannerRepresentable(
            onBarcode: { payload in
                forward(MealCapture(barcodes: [payload]))
            },
            onStill: { image in
                frozenStill = image   // immediate feedback — the OCR takes a beat
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    let lines = await Self.recognizeText(image)
                    forward(MealCapture(ocrLines: lines, imageData: image.jpegData(compressionQuality: 0.6)))
                }
            },
            onFailure: { cameraFailed = true }
        )
        .ignoresSafeArea()
    }

    private var cameraUnavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.textTertiary)
            Text("The camera isn't available.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Check camera access in Settings, then try again.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            // Describing the fix without the door to it is a dead end (principle 13).
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(24)
    }

    /// Still-photo OCR (receipts/labels/plates). Accurate level — this runs once per capture.
    static func recognizeText(_ image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            // Vision can invoke the request's completion (with an error) AND `perform` can
            // still throw for the same request — a checked continuation resumed from both
            // paths traps. `Once` guarantees exactly one resume.
            let once = Once()
            let request = VNRecognizeTextRequest { request, _ in
                guard once.claim() else { return }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                if (try? handler.perform([request])) == nil, once.claim() {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

/// One-shot latch for continuation safety (first `claim` wins, thread-safe).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

// MARK: - DataScanner wrapper

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    let onStill: (UIImage) -> Void
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            DispatchQueue.main.async(execute: onFailure)
            return UIViewController()
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128]),
                .text(),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        context.coordinator.onBarcode = onBarcode
        context.coordinator.onStill = onStill

        // The shutter — the one dominant element (DESIGN-PRINCIPLES 1).
        let shutter = UIButton(type: .custom, primaryAction: UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.captureStill()
        })
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "circle.inset.filled",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 64))
        config.baseForegroundColor = .white
        shutter.configuration = config
        shutter.accessibilityIdentifier = "meal.capture.shutter"
        shutter.translatesAutoresizingMaskIntoConstraints = false
        scanner.overlayContainerView.addSubview(shutter)
        NSLayoutConstraint.activate([
            shutter.centerXAnchor.constraint(equalTo: scanner.overlayContainerView.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: scanner.overlayContainerView.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        weak var scanner: DataScannerViewController?
        var onBarcode: ((String) -> Void)?
        var onStill: ((UIImage) -> Void)?
        private var fired = false

        // Live barcode → auto-advance, once.
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    fired = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dataScanner.stopScanning()
                    onBarcode?(payload)
                    return
                }
            }
        }

        func captureStill() {
            guard let scanner, !fired else { return }
            Task { @MainActor in
                if let photo = try? await scanner.capturePhoto() {
                    fired = true
                    scanner.stopScanning()
                    onStill?(photo)
                }
            }
        }
    }
}

// MARK: - Simulator stand-in

/// The `-simulateMealScan` capture surface: two buttons emitting canned `MealCapture`s that
/// route through the same identify path as the real camera (barcode payload vs OCR lines).
private struct SimulatedCapturePicker: View {
    let onCapture: (MealCapture) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("SIMULATED CAPTURE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            Button {
                onCapture(MealCapture(ocrLines: ["TRADER JOE'S", "CHKN CSR SLD 5.99", "ROTISSERIE CHKN 7.99", "PENNE PASTA 1.49", "LENTIL CURRY 4.99"]))
            } label: {
                Label("Scan a receipt", systemImage: "doc.text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("meal.capture.simulated.receipt")

            Button {
                onCapture(MealCapture(barcodes: ["049000006346"]))
            } label: {
                Label("Scan a barcode", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal.capture.simulated.barcode")

            Button {
                onCapture(MealCapture(ocrLines: [
                    "GREEK YOGURT", "Nutrition Facts", "Serving size 2/3 cup (170g)",
                    "Calories 190", "Total Fat 9g 12%", "Total Carbohydrate 9g 3%", "Protein 17g 34%",
                ]))
            } label: {
                Label("Scan a nutrition label", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal.capture.simulated.label")

            Button {
                onCapture(MealCapture(imageData: Data([0x00])))   // no text, just pixels
            } label: {
                Label("Photo of a plate", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("meal.capture.simulated.plate")
        }
        .padding(32)
    }
}
