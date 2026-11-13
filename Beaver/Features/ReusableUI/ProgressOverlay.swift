import SwiftUI

/// Centered progress for work that keeps the person waiting, like the card Files and Photos
/// show while they save: a spinner (or a bar when the fraction is known), a short title and,
/// for work that really stops, Cancel.
///
/// Touches behind it are blocked from the first frame, but the card and the dimming only
/// appear after `appearanceDelay`, so quick work never flashes it.
struct ProgressOverlay: View {
    let title: String
    /// 0…1 when the work reports it; `nil` shows a spinner.
    var fractionCompleted: Double?
    /// Stops the work. `nil` hides Cancel, for work that can't be stopped.
    var onCancel: (() -> Void)?

    /// How long work runs before the card appears.
    static let appearanceDelay: Duration = .milliseconds(300)

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(isVisible ? Constants.dimmingOpacity : 0))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            if isVisible {
                card
                    .transition(reduceMotion ? .opacity : .scale(scale: Constants.appearScale).combined(with: .opacity))
            }
        }
        .task {
            try? await Task.sleep(for: Self.appearanceDelay)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: Constants.appearDuration)) {
                isVisible = true
            }
            AccessibilityNotification.Announcement(title).post()
        }
    }

    private var card: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // VoiceOver reads the title with the spinner, or with the percentage of the bar.
            Group {
                if let fractionCompleted {
                    ProgressView(value: fractionCompleted)
                        .frame(minWidth: Constants.barWidth)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .accessibilityLabel(title)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)

            if let onCancel {
                Button(DesignSystem.Export.cancel, role: .cancel) {
                    onCancel()
                    AccessibilityNotification.Announcement(DesignSystem.Progress.cancelled).post()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .frame(minHeight: DesignSystem.Layout.minTouchTarget)
                .accessibilityHint(DesignSystem.Progress.cancelHint)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(minWidth: Constants.minimumCardWidth, maxWidth: Constants.maximumCardWidth)
        .background {
            let shape = RoundedRectangle(cornerRadius: Constants.cornerRadius, style: .continuous)
            if reduceTransparency {
                shape.fill(.background)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(Constants.shadowOpacity), radius: Constants.shadowRadius, y: 4)
        .padding(DesignSystem.Spacing.large)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private enum Constants {
    static let dimmingOpacity: Double = 0.2
    static let appearScale: CGFloat = 0.9
    static let appearDuration: Double = 0.2
    static let cornerRadius: CGFloat = 20
    static let minimumCardWidth: CGFloat = 180
    static let maximumCardWidth: CGFloat = 320
    static let barWidth: CGFloat = 160
    static let shadowOpacity: Double = 0.15
    static let shadowRadius: CGFloat = 20
}

#Preview("Cancellable") {
    Color.gray.opacity(0.2)
        .overlay { ProgressOverlay(title: DesignSystem.Progress.splitting, onCancel: {}) }
}

#Preview("Determinate, no Cancel") {
    Color.gray.opacity(0.2)
        .overlay { ProgressOverlay(title: DesignSystem.Progress.exportingPages, fractionCompleted: 0.4) }
}
