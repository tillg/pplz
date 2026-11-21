import SwiftUI

/// A picture to look at closely: pinch to zoom, drag to move it, double-click (or double-tap) to
/// zoom in and back out.
struct ZoomableImage: View {
    let image: Image
    @State private var scale: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag = CGSize.zero

    var body: some View {
        image.resizable().scaledToFit()
            .scaleEffect(scale * pinch)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 8)
                        if scale == 1 { offset = .zero }
                    }
                    .simultaneously(with: DragGesture()
                        .updating($drag) { value, state, _ in if scale > 1 { state = value.translation } }
                        .onEnded { value in
                            guard scale > 1 else { return }
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                        })
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1 { scale = 1; offset = .zero } else { scale = 2.5 }
                }
            }
            .help(String(localized: "Pinch or double-click to zoom, drag to move", bundle: .module))
            .accessibilityLabel(String(localized: "Screenshot", bundle: .module))
    }
}
