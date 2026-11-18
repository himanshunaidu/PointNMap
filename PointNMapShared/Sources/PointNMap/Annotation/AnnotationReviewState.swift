//
//  AnnotationReviewState.swift
//  PointNMapShared
//

public enum AnnotationReviewScope: Hashable, Sendable {
    case all
    case individual
}

public struct AnnotationDecisionSummary: Equatable, Sendable {
    public let keptCount: Int
    public let discardedCount: Int
    public let exceptionCount: Int

    public init(keptCount: Int, discardedCount: Int, exceptionCount: Int) {
        self.keptCount = keptCount
        self.discardedCount = discardedCount
        self.exceptionCount = exceptionCount
    }
}
