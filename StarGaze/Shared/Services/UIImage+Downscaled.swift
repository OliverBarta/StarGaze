//
//  UIImage+Downscaled.swift
//  StarGaze
//

import UIKit

nonisolated extension UIImage {
    /// A copy whose longest side is at most `maxDimension` pixels (never upscaled).
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension, longest > 0 else { return self }

        let ratio = maxDimension / longest
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Downscaled JPEG data, or nil if the image can't be encoded.
    func jpegData(maxDimension: CGFloat, compressionQuality: CGFloat = 0.8) -> Data? {
        downscaled(maxDimension: maxDimension).jpegData(compressionQuality: compressionQuality)
    }
}
