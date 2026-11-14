import UIKit
import Vision
import CoreImage

/// Local-only subject masks. The original UIImage is never overwritten or uploaded.
enum WallpaperForeground {
    enum Outcome {
        case masked(UIImage)
        case noSubject
        case unavailable
    }
    static func hasTransparency(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] < 255 }
    }
    static func process(_ original: UIImage) throws -> Outcome {
        try Task.checkCancellation()
        let normalized: UIImage
        if original.imageOrientation == .up, original.cgImage != nil { normalized = original }
        else {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            normalized = UIGraphicsImageRenderer(size: original.size, format: format).image { _ in
                original.draw(in: CGRect(origin: .zero, size: original.size))
            }
        }
        guard let cg = normalized.cgImage else { return .unavailable }
        // Never re-segment a user-provided alpha cutout.
        if hasTransparency(cg) { return .masked(normalized) }
        #if targetEnvironment(simulator)
        // Vision's foreground model is not guaranteed to exist in the simulator.
        return .unavailable
        #else
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            try Task.checkCancellation()
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return .noSubject }
            let pixelBuffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                                  from: handler, croppedToInstancesExtent: false)
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let output = context.createCGImage(image, from: image.extent), hasTransparency(output) else {
                return .noSubject
            }
            try Task.checkCancellation()
            return .masked(UIImage(cgImage: output))
        } catch is CancellationError { throw CancellationError() }
        catch { return .unavailable }
        #endif
    }
}
