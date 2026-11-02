//
//  AnnotationHelpView.swift
//  PointNMapShared
//

import SwiftUI
import UIKit

enum AnnotationHelpSection: Hashable {
    case overview
    case reviewThisInstance
    case chooseWhatToReview
    case individualChoicesTakePriority
    case viewOrEditDetails
    case inspectImage
    case checkResult
    case keepAndDiscardExamples
    case surfaceDisruption
}

public struct AnnotationHelpConfiguration {
    public let featureClassName: String
    public let isUniquePerCapture: Bool
    public let hasSurfaceDisruption: Bool

    public init(featureClass: AccessibilityFeatureClass) {
        featureClassName = featureClass.name
        isUniquePerCapture = featureClass.kind.isUniquePerCapture
        hasSurfaceDisruption = featureClass.kind.hasSurfaceDisruption
    }

    var sections: [AnnotationHelpSection] {
        var result: [AnnotationHelpSection] = [.overview]

        if isUniquePerCapture {
            result.append(contentsOf: [
                .reviewThisInstance,
                .viewOrEditDetails,
                .inspectImage,
                .checkResult,
                .keepAndDiscardExamples
            ])
        } else {
            result.append(contentsOf: [
                .chooseWhatToReview,
                .individualChoicesTakePriority,
                .viewOrEditDetails,
                .inspectImage,
                .checkResult
            ])
        }

        if hasSurfaceDisruption {
            result.append(.surfaceDisruption)
        }

        return result
    }
}

public struct AnnotationHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let configuration: AnnotationHelpConfiguration

    public init(configuration: AnnotationHelpConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review detected features")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)

                        Text("Check the app’s detections before keeping or discarding them.")
                            .foregroundStyle(.secondary)
                    }

                    if configuration.isUniquePerCapture {
                        uniqueReviewSections
                    } else {
                        groupReviewSections
                    }

                    detailsSection
                    inspectImageSection
                    resultSection

                    if configuration.isUniquePerCapture {
                        examplesSection
                    }

                    if configuration.hasSurfaceDisruption {
                        surfaceDisruptionSection
                    }
                }
                .font(.body)
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Annotation help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var uniqueReviewSections: some View {
        AnnotationHelpSectionView(title: "Review this instance") {
            Text("Review the highlighted area, then choose Keep or Discard.")

            AnnotationHelpIllustration(
                assetName: "annotation_help_unique_review",
                accessibilityDescription: "A sidewalk example with one detected area selected for review."
            )

            Text("In this example, the detected feature is a sidewalk.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var groupReviewSections: some View {
        Group {
            AnnotationHelpSectionView(title: "Choose what to review") {
                Text("'All' sets one decision for the group. 'Individual' lets you choose one detected instance.")

                AnnotationHelpIllustration(
                    assetName: "annotation_help_scope",
                    accessibilityDescription: "The All and Individual control with a pole selected in Individual mode."
                )
            }

            AnnotationHelpSectionView(title: "Individual choices take priority") {
                Text("An individual Keep or Discard choice overrides the group decision.")

                AnnotationHelpIllustration(
                    assetName: "annotation_help_exceptions",
                    accessibilityDescription: "A pole group set to Discard with one pole kept as an individual exception."
                )

                Text("Changing the group keeps individual choices. Use Use group decision to remove an override.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsSection: some View {
        AnnotationHelpSectionView(title: "View or edit details") {
            if configuration.isUniquePerCapture {
                Text("Tap Details to view or edit this instance’s attributes.")
            } else {
                Text("Select Individual and an instance, then tap Details.")
                Text("Details is unavailable while All is selected.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inspectImageSection: some View {
        AnnotationHelpSectionView(title: "Inspect the image") {
            AnnotationHelpIllustration(
                assetName: "annotation_help_overlays",
                accessibilityDescription: "An annotation image shown with and without its detected-area overlay."
            )

            Text("Tap the \(configuration.featureClassName) overlay button to hide the overlay and view the original image.")

            Text("The highlight shows what you are reviewing. Image controls do not change Keep or Discard.")
                .foregroundStyle(.secondary)
        }
    }

    private var resultSection: some View {
        AnnotationHelpSectionView(title: "Check the result") {
            if configuration.isUniquePerCapture {
                Text("The result shows whether this instance will be kept or discarded.")
            } else {
                Text("The summary shows kept and discarded totals, plus how many instances have an individual override.")
                Text("Changing review scope or selecting another instance does not change decisions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var examplesSection: some View {
        AnnotationHelpSectionView(title: "Keep and discard examples") {
            Text("These examples use sidewalk detections.")
                .foregroundStyle(.secondary)

            AnnotationHelpExample(
                assetName: "annotation_example_keep",
                title: "Keep",
                caption: "The highlighted area follows the feature being reviewed.",
                accessibilityDescription: "An accepted sidewalk detection that closely follows the sidewalk."
            )

            Divider()

            AnnotationHelpExample(
                assetName: "annotation_example_borderline",
                title: "Keep — acceptable imperfections",
                caption: "Small gaps can be acceptable when the detected area is still useful.",
                accessibilityDescription: "An accepted sidewalk detection with small localized gaps."
            )

            Divider()

            AnnotationHelpExample(
                assetName: "annotation_example_discard",
                title: "Discard",
                caption: "Discard substantial missing area or clearly incorrect coverage.",
                accessibilityDescription: "A rejected sidewalk detection with substantial missing or incorrect coverage."
            )
        }
    }

    private var surfaceDisruptionSection: some View {
        AnnotationHelpSectionView(title: "Surface disruption") {
            AnnotationHelpIllustration(
                assetName: "annotation_help_surface_disruption",
                accessibilityDescription: "A sidewalk overlay with a separate red area marking a possible surface disruption."
            )

            Text("Red areas show possible surface disruption. Use the Surface disruption button to hide or show them.")

            Text("A disruption prediction alone does not decide Keep or Discard.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AnnotationHelpSectionView<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private struct AnnotationHelpIllustration: View {
    let assetName: String
    let accessibilityDescription: LocalizedStringKey

    var body: some View {
        Image(assetName, bundle: PointNMapSharedResources.bundle)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(Text(accessibilityDescription))
    }
}

private struct AnnotationHelpExample: View {
    let assetName: String
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let accessibilityDescription: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())

            AnnotationHelpIllustration(
                assetName: assetName,
                accessibilityDescription: accessibilityDescription
            )

            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
