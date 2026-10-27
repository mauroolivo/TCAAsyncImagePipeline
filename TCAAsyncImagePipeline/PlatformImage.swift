import SwiftUI
import UIKit

extension DecodedImage {
    var decodedImage: UIImage? {
        guard let decodedImage = UIImage(data: imageData) else {
            AppDiagnostics.log("[PlatformImage] Failed to decode image bytes (\(byteCount)) for \(filename)")
            return nil
        }
        AppDiagnostics.log("[PlatformImage] ✓ Decoded image bytes (\(byteCount)) for \(filename)")
        return decodedImage
    }

    var displayImage: Image? {
        guard let decodedImage = decodedImage else { return nil }
        return Image(uiImage: decodedImage)
    }
}
