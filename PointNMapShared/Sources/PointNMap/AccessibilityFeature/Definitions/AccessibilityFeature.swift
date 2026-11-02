//
//  AnnotatedAccessibilityFeature.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/18/25.
//
import Foundation
import CoreLocation

public enum AccessibilityFeatureError: Error, LocalizedError {
    case attributeValueMismatch(attribute: AccessibilityFeatureAttribute, value: AccessibilityFeatureAttribute.Value)
    case attributeValueNotFinite(attribute: AccessibilityFeatureAttribute, value: Double)
    case attributeValueOutOfRange(
        attribute: AccessibilityFeatureAttribute,
        value: Double,
        minimum: Double?,
        maximum: Double?
    )
    
    public var errorDescription: String? {
        switch self {
        case .attributeValueMismatch(let attribute, let value):
            return "The value \(value) does not match the expected type for attribute \(attribute)."
        case .attributeValueNotFinite(let attribute, let value):
            return "The value \(value) for \(attribute.displayName) must be a finite number."
        case .attributeValueOutOfRange(let attribute, let value, let minimum, let maximum):
            switch (minimum, maximum) {
            case (.some(let minimum), .some(let maximum)):
                return "The value \(value) for \(attribute.displayName) must be between \(minimum) and \(maximum)."
            case (.some(let minimum), nil):
                return "The value \(value) for \(attribute.displayName) must be at least \(minimum)."
            case (nil, .some(let maximum)):
                return "The value \(value) for \(attribute.displayName) must be at most \(maximum)."
            case (nil, nil):
                return "The value \(value) is not valid for \(attribute.displayName)."
            }
        }
    }
}

public protocol AccessibilityFeatureProtocol: Identifiable, Equatable {
    var id: UUID { get }
    
    var accessibilityFeatureClass: AccessibilityFeatureClass { get }
    
    var locationDetails: LocationDetails? { get set }
    
    var attributeValues: [AccessibilityFeatureAttribute: AccessibilityFeatureAttribute.Value?] { get set }
    var experimentalAttributeValues: [AccessibilityFeatureAttribute: AccessibilityFeatureAttribute.Value?] { get set }
    
    func getLastLocationCoordinate() -> CLLocationCoordinate2D?
    
    mutating func setLocationDetails(locationDetails: LocationDetails)
    
    mutating func setAttributeValue(
        _ value: AccessibilityFeatureAttribute.Value,
        for attribute: AccessibilityFeatureAttribute
    ) throws
    mutating func setExperimentalAttributeValue(
        _ value: AccessibilityFeatureAttribute.Value,
        for attribute: AccessibilityFeatureAttribute
    ) throws
}
