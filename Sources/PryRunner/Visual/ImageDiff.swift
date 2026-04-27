import Foundation
import AppKit
import CoreGraphics

/// Tiny image differ for visual regression assertions.
///
/// Compares two PNGs at the same dimensions, returns a percentage of pixels
/// whose RGBA distance exceeds `threshold`. No external deps; uses
/// `CGImageGetData` for raw pixel access.
public enum ImageDiff {

    public struct Result: Sendable {
        public let differingPercent: Double
        public let dimensions: (width: Int, height: Int)
        public let comparable: Bool
        public let reason: String?
    }

    public static func diff(reference refPNG: Data, observed obsPNG: Data,
                            perChannelTolerance: Int = 4) -> Result {
        guard let refImg = cgImage(from: refPNG),
              let obsImg = cgImage(from: obsPNG) else {
            return Result(differingPercent: 1.0, dimensions: (0, 0),
                          comparable: false, reason: "could not decode one of the inputs")
        }
        guard refImg.width == obsImg.width, refImg.height == obsImg.height else {
            return Result(differingPercent: 1.0,
                          dimensions: (refImg.width, refImg.height),
                          comparable: false,
                          reason: "dimensions mismatch: \(refImg.width)×\(refImg.height) vs \(obsImg.width)×\(obsImg.height)")
        }
        guard let refData = pixels(of: refImg),
              let obsData = pixels(of: obsImg) else {
            return Result(differingPercent: 1.0, dimensions: (refImg.width, refImg.height),
                          comparable: false, reason: "could not extract pixel data")
        }
        let total = refImg.width * refImg.height
        var differ = 0
        // RGBA, 4 bytes per pixel.
        let stride = 4
        let len = min(refData.count, obsData.count)
        var i = 0
        while i + stride <= len {
            let dr = abs(Int(refData[i])     - Int(obsData[i]))
            let dg = abs(Int(refData[i + 1]) - Int(obsData[i + 1]))
            let db = abs(Int(refData[i + 2]) - Int(obsData[i + 2]))
            if dr > perChannelTolerance || dg > perChannelTolerance || db > perChannelTolerance {
                differ += 1
            }
            i += stride
        }
        return Result(
            differingPercent: total > 0 ? Double(differ) / Double(total) : 0,
            dimensions: (refImg.width, refImg.height),
            comparable: true,
            reason: nil
        )
    }

    private static func cgImage(from png: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: png as CFData) else { return nil }
        return CGImage(pngDataProviderSource: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func pixels(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes,
                                  width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}
