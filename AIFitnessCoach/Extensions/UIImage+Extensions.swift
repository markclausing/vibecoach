import UIKit

extension UIImage {
    /// Scales (downsamples) the image proportionally so the longest side is no
    /// larger than `maxDimension`. Handy for keeping payloads to APIs small.
    ///
    /// - Parameter maxDimension: The maximum size (in pixels) for the longest side.
    /// - Returns: The downsized UIImage, or the original image if it was already smaller.
    func downsample(to maxDimension: CGFloat = 2048.0) -> UIImage {
        let maxSide = max(size.width, size.height)

        // Only downsize if it's actually larger
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0 // Ensure an exact ratio without forcing Retina scaling

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
