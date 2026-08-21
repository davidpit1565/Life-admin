import SwiftUI
import VisionKit
import Vision
import UIKit

/// Wraps VisionKit's document scanner and runs on-device text recognition on every scanned page,
/// so a photographed bill or letter feeds the exact same free-text pipeline as typed input —
/// nothing leaves the device for the scan itself, only the recognized text goes through the
/// normal (already-gated) extraction path. Also hands back the page images themselves (not just
/// the OCR text) — the scanned insurance policy or warranty card is the thing worth keeping, and
/// text extraction alone would throw it away the moment recognition finished.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanned: (_ recognizedText: String, _ pageImages: [UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanned: (_ recognizedText: String, _ pageImages: [UIImage]) -> Void
        let onCancel: () -> Void

        init(onScanned: @escaping (_ recognizedText: String, _ pageImages: [UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScanned = onScanned
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }
            let callback = onScanned
            DispatchQueue.global(qos: .userInitiated).async {
                let recognizedText = images.compactMap(\.cgImage).map(Self.recognizeText).joined(separator: "\n")
                DispatchQueue.main.async {
                    callback(recognizedText, images)
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }

        private static func recognizeText(in cgImage: CGImage) -> String {
            var result = ""
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                result = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return result
        }
    }
}
