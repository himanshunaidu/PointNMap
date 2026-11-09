//
//  AnnotationReviewInfoTip.swift
//  PointNMapShared
//

import SwiftUI
import TipKit

@available(iOS 17.0, *)
public struct AnnotationReviewInfoTip: Tip {
    public static let viewHelpActionID = "annotation-review-view-help"

    private let isUniquePerCapture: Bool

    public init(isUniquePerCapture: Bool) {
        self.isUniquePerCapture = isUniquePerCapture
    }

    public var title: Text {
        Text("Review detected features")
    }

    public var message: Text? {
        Text(Self.messageText(isUniquePerCapture: isUniquePerCapture))
    }

    public var image: Image? {
        Image(systemName: "info.circle")
    }

    public var actions: [Action] {
        Action(
            id: Self.viewHelpActionID,
            title: "View help"
        )
    }

    public static func messageText(isUniquePerCapture: Bool) -> String {
        if isUniquePerCapture {
            return "Keep the highlighted detection if it represents the real feature. Small gaps are okay; discard it when substantial areas are missing or it covers the wrong area."
        }

        return "Use All to review the group, or Individual to correct one detection. Keep detections that represent real features; discard missing, substantially incomplete, or misplaced detections."
    }
}
