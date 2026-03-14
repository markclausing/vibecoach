import UIKit

extension UIImage {
    /// Verschaalt (downsamples) de afbeelding proportioneel zodat de langste zijde
    /// niet groter is dan `maxDimension`. Handig om payloads naar API's klein te houden.
    ///
    /// - Parameter maxDimension: De maximale grootte (in pixels) voor de langste zijde.
    /// - Returns: De verkleinde UIImage, of de originele afbeelding als deze al kleiner was.
    func downsample(to maxDimension: CGFloat = 2048.0) -> UIImage {
        let maxSide = max(size.width, size.height)

        // Alleen verkleinen als het echt groter is
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0 // Zorg voor een exacte verhouding zonder Retina-scaling te forceren

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
