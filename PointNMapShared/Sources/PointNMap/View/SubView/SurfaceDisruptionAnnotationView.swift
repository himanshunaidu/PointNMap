//
//  SurfaceDisruptionAnnotationView.swift
//  PointNMapShared
//

import SwiftUI

public struct SurfaceDisruptionAnnotationView: View {
    @ObservedObject private var model: SurfaceDisruptionAnnotationViewModel

    public init(model: SurfaceDisruptionAnnotationViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 16) {
            SurfaceDisruptionScopePicker(model: model)

            if model.regions.isEmpty {
                SurfaceDisruptionEmptyState()
            } else {
                switch model.reviewScope {
                case .all:
                    SurfaceDisruptionGroupControls(model: model)
                case .individual:
                    SurfaceDisruptionIndividualControls(model: model)
                }

                SurfaceDisruptionDecisionSummaryView(summary: model.decisionSummary)
            }
        }
    }
}

private struct SurfaceDisruptionScopePicker: View {
    @ObservedObject var model: SurfaceDisruptionAnnotationViewModel

    var body: some View {
        Picker(
            "Surface disruption review scope",
            selection: Binding(
                get: { model.reviewScope },
                set: model.setReviewScope
            )
        ) {
            Text("All (\(model.regions.count))", bundle: #bundle)
                .tag(AnnotationReviewScope.all)
            Text("Individual", bundle: #bundle)
                .tag(AnnotationReviewScope.individual)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Surface disruption review scope")
        .accessibilityHint("Choose whether decisions apply to every region or one region")
    }
}

private struct SurfaceDisruptionGroupControls: View {
    @ObservedObject var model: SurfaceDisruptionAnnotationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apply a decision to all surface disruptions", bundle: #bundle)
                .font(.subheadline.weight(.semibold))

            SurfaceDisruptionDecisionButton(
                decision: .keep,
                isGroupAction: true,
                isSelected: model.groupDecision == .keep,
                action: { model.setGroupDecision(.keep) }
            )
            SurfaceDisruptionDecisionButton(
                decision: .discard,
                isGroupAction: true,
                isSelected: model.groupDecision == .discard,
                action: { model.setGroupDecision(.discard) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SurfaceDisruptionIndividualControls: View {
    @ObservedObject var model: SurfaceDisruptionAnnotationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                "Surface disruption region",
                selection: Binding(
                    get: { model.currentRegionID },
                    set: { regionID in
                        if let regionID {
                            model.selectRegion(id: regionID)
                        }
                    }
                )
            ) {
                ForEach(model.regions) { region in
                    Text("Surface Disruption #\(regionNumber(for: region))", bundle: #bundle)
                        .tag(Optional(region.id))
                }
            }
            .accessibilityLabel("Surface disruption region")
            .accessibilityHint("Select a detected surface disruption to review")

            if let region = model.currentRegion {
                SurfaceDisruptionEffectiveDecisionView(
                    decision: model.effectiveDecision(for: region),
                    isOverride: model.currentIndividualDecision != nil,
                    areaSquareMeters: region.areaSquareMeters
                )

                Text("Override for this surface disruption", bundle: #bundle)
                    .font(.subheadline.weight(.semibold))

                SurfaceDisruptionDecisionButton(
                    decision: .keep,
                    isGroupAction: false,
                    isSelected: model.currentIndividualDecision == .keep,
                    action: { model.setIndividualDecision(.keep) }
                )
                SurfaceDisruptionDecisionButton(
                    decision: .discard,
                    isGroupAction: false,
                    isSelected: model.currentIndividualDecision == .discard,
                    action: { model.setIndividualDecision(.discard) }
                )

                Button {
                    model.clearIndividualDecision()
                } label: {
                    Text("Use Group Decision", bundle: #bundle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Removes the individual override for this region")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func regionNumber(for region: SurfaceDisruptionRegion) -> Int {
        let index = model.regions.firstIndex(where: { $0.id == region.id }) ?? 0
        return index + 1
    }
}

private struct SurfaceDisruptionEffectiveDecisionView: View {
    let decision: AnnotationDecision
    let isOverride: Bool
    let areaSquareMeters: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: decision == .keep ? "checkmark.circle.fill" : "trash.circle.fill")
                .foregroundStyle(decision == .keep ? .green : .red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if decision == .keep {
                    Text("Kept", bundle: #bundle)
                        .font(.headline)
                } else {
                    Text("Discarded", bundle: #bundle)
                        .font(.headline)
                }
                if isOverride {
                    Text("Individual override", bundle: #bundle)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Group decision", bundle: #bundle)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Area: \(areaSquareMeters, format: .number.precision(.fractionLength(0...3))) m²",
                    bundle: #bundle
                )
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Effective decision")
        .accessibilityValue(
            decision == .keep
                ? "Kept, \(isOverride ? "individual override" : "group decision")"
                : "Discarded, \(isOverride ? "individual override" : "group decision")"
        )
    }
}

private struct SurfaceDisruptionDecisionButton: View {
    let decision: AnnotationDecision
    let isGroupAction: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                if isGroupAction {
                    if decision == .keep {
                        Text("Keep All", bundle: #bundle)
                    } else {
                        Text("Discard All", bundle: #bundle)
                    }
                } else {
                    if decision == .keep {
                        Text("Keep", bundle: #bundle)
                    } else {
                        Text("Discard", bundle: #bundle)
                    }
                }
            } icon: {
                Image(systemName: decision == .keep ? "checkmark" : "trash")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .opacity(isSelected ? 1 : 0.65)
        .tint(decision == .keep ? .green : .red)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(
            isGroupAction
                ? "Applies this decision to every surface disruption"
                : "Overrides the group decision for the selected surface disruption"
        )
    }
}

private struct SurfaceDisruptionDecisionSummaryView: View {
    let summary: AnnotationDecisionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Surface disruption summary", bundle: #bundle)
                .font(.subheadline.weight(.semibold))
            Text("\(summary.keptCount) kept", bundle: #bundle)
            Text("\(summary.discardedCount) discarded", bundle: #bundle)
            Text("\(summary.exceptionCount) overrides", bundle: #bundle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Surface disruption decision summary")
        .accessibilityValue(
            "\(summary.keptCount) kept, \(summary.discardedCount) discarded, \(summary.exceptionCount) overrides"
        )
    }
}

private struct SurfaceDisruptionEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No surface disruptions to review", bundle: #bundle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("The completed analysis did not produce any valid disruption regions.", bundle: #bundle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}
