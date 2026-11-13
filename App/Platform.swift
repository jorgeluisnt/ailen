import SwiftUI

// Cross-platform shims for the native macOS build. The iOS code is the
// reference; these give macOS equivalents for the handful of UIKit types and
// iOS-only SwiftUI modifiers the shared views use, so those views compile on
// both platforms without `#if` at every call site.

#if os(macOS)
import AppKit

typealias PlatformImage = NSImage

extension NSImage {
    /// UIKit-style initialiser; AppKit sizes the image from the bitmap.
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}

extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}

/// Points → pixels for the main display (Retina = 2).
@MainActor var platformScreenScale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

extension ToolbarItemPlacement {
    /// iOS bar placements, mapped to their macOS window-toolbar equivalents.
    // `.navigation` squeezes items against the traffic lights in this
    // window layout; keep them with the other toolbar buttons instead.
    static var topBarLeading: ToolbarItemPlacement { .primaryAction }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

/// macOS has no inline/large navigation titles; the iOS modifier is a no-op.
enum NavigationBarItem {
    enum TitleDisplayMode { case automatic, inline, large }
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }
}

#else
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}

@MainActor var platformScreenScale: CGFloat { UIScreen.main.scale }
#endif
