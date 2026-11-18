//
//  SurfaceDisruptionAnnotationViewModel.swift
//  PointNMapShared
//

import Combine

public enum SurfaceDisruptionReviewMode: Hashable, Sendable {
    case sidewalk
    case disruptions
}

@MainActor
public final class SurfaceDisruptionAnnotationViewModel: ObservableObject {
    @Published public private(set) var reviewMode: SurfaceDisruptionReviewMode = .sidewalk
    @Published public private(set) var reviewScope: AnnotationReviewScope = .all
    @Published public private(set) var regions: [SurfaceDisruptionRegion] = []
    @Published public private(set) var currentRegionID: SurfaceDisruptionRegion.ID?
    @Published public private(set) var groupDecision: AnnotationDecision = .keep

    @Published private var individualDecisions: [SurfaceDisruptionRegion.ID: AnnotationDecision] = [:]

    public init(regions: [SurfaceDisruptionRegion] = []) {
        setRegions(regions)
    }

    public var currentRegion: SurfaceDisruptionRegion? {
        guard let currentRegionID else {
            return nil
        }
        return regions.first { $0.id == currentRegionID }
    }

    public var currentIndividualDecision: AnnotationDecision? {
        guard let currentRegionID else {
            return nil
        }
        return individualDecisions[currentRegionID]
    }

    public var decisionSummary: AnnotationDecisionSummary {
        regions.reduce(
            into: AnnotationDecisionSummary(keptCount: 0, discardedCount: 0, exceptionCount: 0)
        ) { summary, region in
            let decision = effectiveDecision(for: region)
            let isException = individualDecisions[region.id].map { $0 != groupDecision } ?? false

            summary = AnnotationDecisionSummary(
                keptCount: summary.keptCount + (decision == .keep ? 1 : 0),
                discardedCount: summary.discardedCount + (decision == .discard ? 1 : 0),
                exceptionCount: summary.exceptionCount + (isException ? 1 : 0)
            )
        }
    }

    public var acceptedAreaSquareMeters: Double {
        regions.reduce(into: 0) { area, region in
            if effectiveDecision(for: region) == .keep {
                area += region.areaSquareMeters
            }
        }
    }

    public func setRegions(_ regions: [SurfaceDisruptionRegion]) {
        self.regions = regions

        let validIDs = Set(regions.map(\.id))
        individualDecisions = individualDecisions.filter { validIDs.contains($0.key) }

        if let currentRegionID, validIDs.contains(currentRegionID) {
            return
        }
        currentRegionID = regions.first?.id
    }

    public func setReviewMode(_ reviewMode: SurfaceDisruptionReviewMode) {
        self.reviewMode = reviewMode
    }

    public func setReviewScope(_ reviewScope: AnnotationReviewScope) {
        self.reviewScope = reviewScope
    }

    public func selectRegion(id: SurfaceDisruptionRegion.ID) {
        guard regions.contains(where: { $0.id == id }) else {
            return
        }
        currentRegionID = id
    }

    public func setGroupDecision(_ decision: AnnotationDecision) {
        groupDecision = decision
    }

    public func setIndividualDecision(_ decision: AnnotationDecision) {
        guard let currentRegionID else {
            return
        }
        individualDecisions[currentRegionID] = decision
    }

    public func clearIndividualDecision() {
        guard let currentRegionID else {
            return
        }
        individualDecisions.removeValue(forKey: currentRegionID)
    }

    public func effectiveDecision(for region: SurfaceDisruptionRegion) -> AnnotationDecision {
        individualDecisions[region.id] ?? groupDecision
    }
}

public func isSurfaceDisruptionReviewAvailable<Analysis>(
    featureClass: AccessibilityFeatureClass,
    selectedAttributes: Set<AccessibilityFeatureAttribute>,
    analysis: Analysis?
) -> Bool {
    featureClass.kind == .sidewalk
        && selectedAttributes.contains(.surfaceDisruptionArea)
        && analysis != nil
}
