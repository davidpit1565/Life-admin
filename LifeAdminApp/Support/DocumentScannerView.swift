import SwiftUI
import VisionKit
import Vision

/// Wraps VisionKit's document scanner and runs on-device text recognition on every scanned page,
/// so a photographed bill or letter feeds the exact same free-text pipeline as typed input —
/// nothing leaves the device for the scan itself, only the recognized text goes through the
/// normal (already-gated) extraction path.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onRecognizedText: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognizedText: onRecognizedText, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onRecognizedText: (String) -> Void
        let onCancel: () -> Void

        init(onRecognizedText: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onRecognizedText = onRecognizedText
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [CGImage] = []
            for pageIndex in 0..<scan.pageCount {
                if let cgImage = scan.imageOfPage(at: pageIndex).cgImage {
                    images.append(cgImage)
                }
            }
            let callback = onRecognizedText
            DispatchQueue.global(qos: .userInitiated).async {
                let recognizedText = images.map(Self.recognizeText).joined(separator: "\n")
                DispatchQueue.main.async {
                    callback(recognizedText)
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
