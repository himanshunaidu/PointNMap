//
//  AnnotationOverlayLegendView.swift
//  PointNMapShared
//

import SwiftUI

public struct AnnotationOverlayLegendView: View {
    private let featureClass: AccessibilityFeatureClass
    @Binding private var isSegmentationOverlayVisible: Bool
    @Binding private var isSurfaceAnalysisOverlayVisible: Bool

    public init(
        featureClass: AccessibilityFeatureClass,
        isSegmentationOverlayVisible: Binding<Bool>,
        isSurfaceAnalysisOverlayVisible: Binding<Bool>
    ) {
        self.featureClass = featureClass
        _isSegmentationOverlayVisible = isSegmentationOverlayVisible
        _isSurfaceAnalysisOverlayVisible = isSurfaceAnalysisOverlayVisible
    }

    public var body: some View {
        HStack(spacing: 8) {
            overlayButton(
                title: "Segmentation",
                color: Color(
                    red: Double(featureClass.color.red),
                    green: Double(featureClass.color.green),
                    blue: Double(featureClass.color.blue),
                    opacity: Double(featureClass.color.alpha)
                ),
                isVisible: isSegmentationOverlayVisible
            ) {
                isSegmentationOverlayVisible.toggle()
            }

            if featureClass.kind.hasSurfaceDisruption {
                overlayButton(
                    title: "Surface disruption",
                    color: .red,
                    isVisible: isSurfaceAnalysisOverlayVisible
                ) {
                    isSurfaceAnalysisOverlayVisible.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background)
    }

    private func overlayButton(
        title: String,
        color: Color,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(.primary.opacity(0.2), lineWidth: 1)
                    }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                    .imageScale(.small)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isVisible ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isVisible ? color.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        isVisible ? color.opacity(0.8) : Color.secondary.opacity(0.25),
                        lineWidth: isVisible ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isVisible ? "Shown" : "Hidden"))
        .accessibilityHint(Text("Toggles this image overlay"))
    }
}
