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
        HStack(spacing: 8) {
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
    }
}

private struct SurfaceDisruptionIndividualControls: View {
    @ObservedObject var model: SurfaceDisruptionAnnotationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Surface disruption region")
                .accessibilityHint("Select a detected surface disruption to review")

                if let region = model.currentRegion {
                    Text(
                        "\(region.areaSquareMeters, format: .number.precision(.fractionLength(0...3))) m²",
                        bundle: #bundle
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("Area")
                    .accessibilityValue(
                        "\(region.areaSquareMeters, format: .number.precision(.fractionLength(0...3))) square meters"
                    )
                }
            }

            if let region = model.currentRegion {
                SurfaceDisruptionEffectiveDecisionView(
                    decision: model.effectiveDecision(for: region),
                    isOverride: model.currentIndividualDecision != nil,
                    clearOverride: model.clearIndividualDecision
                )

                HStack(spacing: 8) {
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
                }
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
    let clearOverride: () -> Void

    var body: some View {
        let decisionColor: Color = decision == .keep ? .green : .red

        HStack(spacing: 12) {
            Label {
                HStack(spacing: 4) {
                    Text(decision == .keep ? "Keep" : "Discard", bundle: #bundle)
                        .fontWeight(.semibold)
                    Text(isOverride ? "(Override)" : "(Group)", bundle: #bundle)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: decision == .keep ? "checkmark" : "trash")
            }
            .foregroundStyle(decisionColor)

            Spacer(minLength: 0)

            Button(action: clearOverride) {
                Text("Use Group Decision", bundle: #bundle)
            }
            .buttonStyle(.bordered)
            .disabled(!isOverride)
            .accessibilityHint("Removes the individual override for this region")
        }
        .font(.subheadline)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(decisionColor.opacity(0.1))
        )
    }
}

private struct SurfaceDisruptionDecisionButton: View {
    let decision: AnnotationDecision
    let isGroupAction: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let decisionColor: Color = decision == .keep ? .green : .red

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
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(decisionColor)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(decisionColor.opacity(isSelected ? 0.18 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        decisionColor.opacity(isSelected ? 1 : 0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 8) {
            Text("\(summary.keptCount) kept", bundle: #bundle)
                .foregroundStyle(.green)
            Text("·")
                .accessibilityHidden(true)
            Text("\(summary.discardedCount) discarded", bundle: #bundle)
                .foregroundStyle(.red)
            Text("·")
                .accessibilityHidden(true)
            Text("\(summary.exceptionCount) exceptions", bundle: #bundle)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Surface disruption decision summary")
        .accessibilityValue(
            "\(summary.keptCount) kept, \(summary.discardedCount) discarded, \(summary.exceptionCount) exceptions"
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
