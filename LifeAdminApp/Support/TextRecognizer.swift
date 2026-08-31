import Vision
import UIKit

/// On-device text recognition shared by every source of a document image — the camera-based
/// document scanner (`DocumentScannerView`) and a photo/file attached directly to an existing
/// item (`ItemDetailView`'s auto-fill). Nothing here ever leaves the device; only the recognized
/// text itself is handed onward to each caller's own (already-gated, consent-respecting)
/// extraction pipeline — this type only ever reads pixels already sitting in the app's own
/// memory or file system, never a network call of its own.
enum TextRecognizer {
    static func recognizeText(in image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }
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
