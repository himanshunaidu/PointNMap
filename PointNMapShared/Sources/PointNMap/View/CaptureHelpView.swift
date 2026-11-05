import SwiftUI

enum CaptureHelpAsset: String, CaseIterable {
    case objectGood = "capture_help_object_good"
    case objectAdjust = "capture_help_object_adjust"
    case sidewalkDirection = "capture_help_sidewalk_direction"
    case sidewalkGood = "capture_help_sidewalk_good"
    case sidewalkAdjust = "capture_help_sidewalk_adjust"

    var name: String { rawValue }
}

public struct CaptureHelpView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    CaptureHelpIntroduction()
                    CaptureHelpObjectsSection()
                    CaptureHelpSidewalkSection()
                    CaptureHelpReadinessCallout()
                }
                .font(.body)
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(
                Text(
                    "Capture help",
                    bundle: PointNMapSharedResources.bundle,
                    comment: "Title of the help sheet for taking a capture."
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(
                            "Done",
                            bundle: PointNMapSharedResources.bundle,
                            comment: "Button that closes the Capture help sheet."
                        )
                    }
                }
            }
        }
    }
}

private struct CaptureHelpIntroduction: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "Tips for a good capture",
                bundle: PointNMapSharedResources.bundle,
                comment: "Heading introducing general Capture guidance."
            )
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)

            Text(
                "Capture when the highlighted areas line up with the real features you want to record.",
                bundle: PointNMapSharedResources.bundle,
                comment: "Introduction explaining when a person should take a capture."
            )
            .foregroundStyle(.secondary)
        }
    }
}

private struct CaptureHelpObjectsSection: View {
    var body: some View {
        CaptureHelpSectionCard(
            title: "Objects such as poles and signs",
            titleComment: "Heading for guidance about capturing objects such as poles and signs."
        ) {
            Text(
                "Check that the highlight follows the real object you want to capture, rather than the surrounding background.",
                bundle: PointNMapSharedResources.bundle,
                comment: "Instruction for judging the highlight around a captured object."
            )

            CaptureHelpAdaptiveComparison(
                first: CaptureHelpExampleCard(
                    asset: .objectGood,
                    title: "Good capture",
                    titleComment: "Label for an acceptable Capture example.",
                    caption: "The highlight follows the object.",
                    captionComment: "Caption for an acceptable object-highlight example."
                ),
                second: CaptureHelpExampleCard(
                    asset: .objectAdjust,
                    title: "Adjust before capturing",
                    titleComment: "Label for a Capture example that needs adjustment.",
                    caption: "The highlight misses the object or includes too much of the background.",
                    captionComment: "Caption for an object highlight that is not aligned well enough."
                )
            )
        }
    }
}

private struct CaptureHelpSidewalkSection: View {
    var body: some View {
        CaptureHelpSectionCard(
            title: "Sidewalks",
            titleComment: "Heading for sidewalk-specific Capture guidance."
        ) {
            CaptureHelpSubheading(
                title: "Aim along the sidewalk",
                comment: "Subheading for camera-direction guidance when capturing a sidewalk."
            )

            Text(
                "Point the camera in the direction the sidewalk continues, keeping the sidewalk ahead visible. Avoid aiming across the sidewalk or only straight down at your feet.",
                bundle: PointNMapSharedResources.bundle,
                comment: "Instruction for aiming the camera while capturing a sidewalk."
            )

            CaptureHelpPendingIllustration(asset: .sidewalkDirection)

            Divider()

            CaptureHelpSubheading(
                title: "Check the sidewalk highlight",
                comment: "Subheading for judging the highlighted sidewalk area."
            )

            Text(
                "The highlight should mostly follow the real sidewalk. Small, localized gaps may be acceptable; large missing areas or substantial highlighting outside the sidewalk are not.",
                bundle: PointNMapSharedResources.bundle,
                comment: "Instruction for deciding whether a sidewalk highlight is suitable for capture."
            )

            CaptureHelpAdaptiveComparison(
                first: CaptureHelpExampleCard(
                    asset: .sidewalkGood,
                    title: "Good capture",
                    titleComment: "Label for an acceptable Capture example.",
                    caption: "The highlight follows the sidewalk and its important boundaries.",
                    captionComment: "Caption for an acceptable sidewalk-highlight example."
                ),
                second: CaptureHelpExampleCard(
                    asset: .sidewalkAdjust,
                    title: "Adjust before capturing",
                    titleComment: "Label for a Capture example that needs adjustment.",
                    caption: "Large parts of the sidewalk are missing, or the highlight extends onto other surfaces.",
                    captionComment: "Caption for a sidewalk highlight that is not aligned well enough."
                )
            )
        }
    }
}

private struct CaptureHelpReadinessCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Ready does not mean verified",
                    bundle: PointNMapSharedResources.bundle,
                    comment: "Heading clarifying what Ready to capture means."
                )
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

                Text(
                    "“Ready to capture” means the app can accept a capture. It does not confirm that the highlighted features are correct. Check the live image before tapping the camera button.",
                    bundle: PointNMapSharedResources.bundle,
                    comment: "Explanation that capture readiness does not verify highlight accuracy."
                )

                Text(
                    "You can review the captured detections on the next screen.",
                    bundle: PointNMapSharedResources.bundle,
                    comment: "Supporting reminder that detections can be reviewed after capture."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private struct CaptureHelpSectionCard<Content: View>: View {
    let title: LocalizedStringKey
    let titleComment: StaticString
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        titleComment: StaticString,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleComment = titleComment
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                title,
                bundle: PointNMapSharedResources.bundle,
                comment: titleComment
            )
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

private struct CaptureHelpSubheading: View {
    let title: LocalizedStringKey
    let comment: StaticString

    var body: some View {
        Text(
            title,
            bundle: PointNMapSharedResources.bundle,
            comment: comment
        )
        .font(.subheadline.bold())
        .accessibilityAddTraits(.isHeader)
    }
}

private struct CaptureHelpAdaptiveComparison<First: View, Second: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let first: First
    let second: Second

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalLayout
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    first
                        .frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)
                    second
                        .frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)
                }

                verticalLayout
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            first
            second
        }
    }
}

private struct CaptureHelpExampleCard: View {
    let asset: CaptureHelpAsset
    let title: LocalizedStringKey
    let titleComment: StaticString
    let caption: LocalizedStringKey
    let captionComment: StaticString

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                title,
                bundle: PointNMapSharedResources.bundle,
                comment: titleComment
            )
            .font(.subheadline.bold())

            CaptureHelpPlaceholderImage(asset: asset)

            Text(
                "Approved example image pending.",
                bundle: PointNMapSharedResources.bundle,
                comment: "Temporary status shown until an approved Capture example replaces the placeholder."
            )
            .font(.callout)

            Text(
                caption,
                bundle: PointNMapSharedResources.bundle,
                comment: captionComment
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CaptureHelpPendingIllustration: View {
    let asset: CaptureHelpAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CaptureHelpPlaceholderImage(asset: asset)

            Text(
                "Approved direction example pending.",
                bundle: PointNMapSharedResources.bundle,
                comment: "Temporary status shown until an approved sidewalk-direction example replaces the placeholder."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CaptureHelpPlaceholderImage: View {
    let asset: CaptureHelpAsset

    var body: some View {
        Image(asset.name, bundle: PointNMapSharedResources.bundle)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}
