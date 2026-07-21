//
//  AccessibilityFeatureKind.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 4/30/26.
//

/**
 AccessibilityFeatureKind refers to the semantic type of the feature that you would find in an environment where the feature is being captured.
 */
public enum AccessibilityFeatureKind: String, Identifiable, Codable, CaseIterable, Equatable, Sendable {
    case sidewalk = "sidewalk"
    case building = "building"
    case pole = "pole"
    case trafficLight = "traffic_light"
    case trafficSign = "traffic_sign"
    case curbRamp = "curb_ramp"
    case vegetation = "vegetation"
    case unknown = "unknown"
    
    public var id: String {
        return self.rawValue
    }
    
    public var geometry: MappingGeometry {
        switch self {
        case .sidewalk: return .linestring
        case .building: return .polygon
        case .pole, .trafficLight, .trafficSign, .curbRamp: return .point
        default: return .point
        }
    }
    
    /// Attributes associated with the accessibility feature class
    public var attributes: Set<AccessibilityFeatureAttribute>
    {
        switch self {
        case .sidewalk: return [
            .width, .runningSlope, .crossSlope,
//            .surfaceIntegrity,
            .surfaceDisruption, .heightFromGround,
            .widthLegacy, .runningSlopeLegacy, .crossSlopeLegacy,
            .widthFromImage, .runningSlopeFromImage, .crossSlopeFromImage
        ]
        case .curbRamp: return [
            .width, .runningSlope, .crossSlope,
//            .widthLegacy, .runningSlopeLegacy, .crossSlopeLegacy,
            .widthFromImage, .runningSlopeFromImage, .crossSlopeFromImage
        ]
        default : return []
        }
    }
    
    /// Experimental attributes associated with the accessibility feature class
    public var experimentalAttributes: Set<AccessibilityFeatureAttribute> {
        switch self {
            default : return []
        }
    }
    
    /// Some feature kinds should only have one instance captured per image, while others can have multiple instances.
    /// This property indicates whether the feature kind is unique per image.
    /// MARK: Can later be updated to even support the maximum number of instances per image, if needed,
    ///     since it is impractical to have more than a certain number of instances of a feature in a single image.
    public var isUniquePerCapture: Bool {
        switch self {
        case .sidewalk, .curbRamp:
            return true
        default:
            return false
        }
    }
}

extension AccessibilityFeatureKind {
    public static let `default`: AccessibilityFeatureKind = .unknown
}
