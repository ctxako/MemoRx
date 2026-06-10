import SwiftUI

extension View {
    /// Fades list content at the top and bottom so rows don’t look hard-cut under the large title or tab bar.
    func drugListScrollEdgeFade() -> some View {
        mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.035),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
