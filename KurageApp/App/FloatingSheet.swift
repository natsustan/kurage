import SwiftUI

enum FloatingSheetDetent: Equatable {
    case medium
    case expanded
}

/// A transparent modal keeps the surface's bottom corners and outside margin
/// visible at both heights, independently of the system sheet material.
struct FloatingSheet<Content: View>: View {
    private let selection: Binding<FloatingSheetDetent>?
    private let allowsExpansion: Bool
    private let showsDragIndicator: Bool
    private let background: Color
    private let content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localDetent: FloatingSheetDetent
    @GestureState private var dragOffset: CGFloat = 0

    init(selection: Binding<FloatingSheetDetent>? = nil, initialDetent: FloatingSheetDetent = .medium,
         allowsExpansion: Bool = true, showsDragIndicator: Bool = true,
         background: Color = Color(uiColor: .systemBackground), @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.allowsExpansion = allowsExpansion
        self.showsDragIndicator = showsDragIndicator
        self.background = background
        self.content = content()
        _localDetent = State(initialValue: initialDetent)
    }

    private var detent: FloatingSheetDetent { selection?.wrappedValue ?? localDetent }
    private var animation: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = horizontalSizeClass == .compact
            let availableHeight = max(0, geometry.size.height - 24)
            let expandedHeight = isCompact ? availableHeight * 0.95 : min(availableHeight, 880)
            let height = detent == .medium ? expandedHeight * 0.55 : expandedHeight

            ZStack(alignment: isCompact ? .bottom : .center) {
                Button { dismiss() } label: {
                    Color.black.opacity(0.3)
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityLabel("Dismiss sheet")
                .accessibilityIdentifier("dismiss-floating-sheet")

                VStack(spacing: 0) {
                    if showsDragIndicator {
                        Button {
                            if allowsExpansion {
                                setDetent(detent == .medium ? .expanded : .medium)
                            }
                        } label: {
                            Capsule()
                                .fill(.secondary.opacity(0.4))
                                .frame(width: 36, height: 5)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sheet Grabber")
                        .accessibilityValue(detent == .medium ? "Half screen" : "Expanded")
                        .accessibilityAdjustableAction { direction in
                            guard allowsExpansion else { return }
                            switch direction {
                            case .increment: setDetent(.expanded)
                            case .decrement: setDetent(.medium)
                            @unknown default: break
                            }
                        }
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: min(max(0, geometry.size.width - 16), isCompact ? .infinity : 600), height: height)
                .background(background)
                .clipShape(.rect(cornerRadius: 36))
                .offset(y: dragOffset)
                .simultaneousGesture(headerDrag)
                .padding(.vertical, 12)
                .animation(animation, value: detent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationBackground(.clear)
    }

    // Keep scrolling, pull-to-refresh and navigation gestures in the content.
    // Resizing and swipe-to-dismiss belong to the top of the surface.
    private var headerDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, offset, _ in
                guard value.startLocation.y < 64,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                offset = min(160, max(0, value.translation.height))
            }
            .onEnded { value in
                guard value.startLocation.y < 64,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height < -50, allowsExpansion {
                    setDetent(.expanded)
                } else if value.translation.height > 50 || value.predictedEndTranslation.height > 160 {
                    if detent == .expanded, allowsExpansion {
                        setDetent(.medium)
                    } else {
                        dismiss()
                    }
                }
            }
    }

    private func setDetent(_ value: FloatingSheetDetent) {
        if let selection { selection.wrappedValue = value }
        else { localDetent = value }
    }
}
