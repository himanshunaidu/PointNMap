import SwiftUI

public enum CapturePresentationState: Equatable, Sendable {
    case preparing
    case ready
    case unavailable(explanation: String)
    case processing
    case captureFailed(explanation: String)

    public var isCaptureEnabled: Bool {
        switch self {
        case .ready, .captureFailed:
            return true
        case .preparing, .unavailable, .processing:
            return false
        }
    }

    public var showsActivityIndicator: Bool {
        switch self {
        case .preparing, .processing:
            return true
        case .ready, .unavailable, .captureFailed:
            return false
        }
    }

    public var isWarning: Bool {
        switch self {
        case .unavailable, .captureFailed:
            return true
        case .preparing, .ready, .processing:
            return false
        }
    }

    public var heading: String {
        switch self {
        case .preparing:
            return "Preparing capture…"
        case .ready:
            return "Ready to capture"
        case .unavailable:
            return "Capture unavailable"
        case .processing:
            return "Processing capture…"
        case .captureFailed:
            return "Capture unsuccessful"
        }
    }

    public var explanation: String {
        switch self {
        case .preparing:
            return "Setting up capture and analysis."
        case .ready:
            return "Capture when the highlighted features look right."
        case .unavailable(let explanation), .captureFailed(let explanation):
            return explanation
        case .processing:
            return "Preparing your annotation."
        }
    }
}

public struct CaptureControlPanel: View {
    public let state: CapturePresentationState
    private let captureAction: () -> Void
    private let helpAction: () -> Void

    public init(
        state: CapturePresentationState,
        captureAction: @escaping () -> Void,
        helpAction: @escaping () -> Void
    ) {
        self.state = state
        self.captureAction = captureAction
        self.helpAction = helpAction
    }

    public var body: some View {
        VStack(spacing: 14) {
            CaptureStatusView(state: state)

            Button(action: captureAction) {
                Image(systemName: "camera.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(state.isCaptureEnabled ? Color.accentColor : Color.secondary)
            }
            .disabled(!state.isCaptureEnabled)
            .accessibilityLabel("Capture")
            .accessibilityHint(captureAccessibilityHint)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button(action: helpAction) {
                    Image(systemName: "info.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Capture help")
                .accessibilityHint("Opens information about capturing accessibility features.")
            }
            .frame(minHeight: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private var captureAccessibilityHint: String {
        state.isCaptureEnabled
            ? "Captures the current camera view for annotation."
            : state.explanation
    }
}

public struct CaptureStatusView: View {
    public let state: CapturePresentationState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let statusHeight: CGFloat = 72

    public init(state: CapturePresentationState) {
        self.state = state
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                indicator
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.heading)
                        .font(.headline)
                        .foregroundStyle(state.isWarning ? .primary : .secondary)

                    Text(state.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: statusHeight, maxHeight: statusHeight, alignment: .leading)
        .background(
            state.isWarning ? Color.orange.opacity(0.14) : Color.green.opacity(0.14),// Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var indicator: some View {
        if state.showsActivityIndicator {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: state.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(state.isWarning ? .orange : .green)
        }
    }
}
