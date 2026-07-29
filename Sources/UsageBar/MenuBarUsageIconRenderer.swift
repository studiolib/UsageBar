import AppKit

enum MenuBarUsageIconRenderer {
    static func image(
        claudeRemainingPercent: Double?,
        codexRemainingPercent: Double?) -> NSImage
    {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            drawBar(
                in: NSRect(x: 3, y: 10, width: 20, height: 5),
                remainingPercent: claudeRemainingPercent)
            drawBar(
                in: NSRect(x: 3, y: 3, width: 20, height: 5),
                remainingPercent: codexRemainingPercent)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Claude and Codex usage remaining"
        return image
    }

    private static func drawBar(in rect: NSRect, remainingPercent: Double?) {
        let radius = rect.height / 2
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.55).setFill()
        trackPath.fill()

        let fraction = max(0, min((remainingPercent ?? 0) / 100, 1))
        guard fraction > 0 else { return }

        let fillRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.height, rect.width * fraction),
            height: rect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        NSColor.labelColor.setFill()
        fillPath.fill()
    }
}
