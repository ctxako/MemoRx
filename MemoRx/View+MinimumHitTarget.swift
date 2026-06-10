import SwiftUI

extension View {
    /// Keeps interactive controls at or above Apple's recommended minimum touch target.
    func minimumHitTarget(_ size: CGFloat = 44) -> some View {
        frame(minWidth: size, minHeight: size)
    }
}
