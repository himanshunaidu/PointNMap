//
//  AccessibilityFeatureAttribute.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/9/25.
//

import Foundation

/**
    Enumeration defining various accessibility feature attributes, along with their metadata and value types.
 
    - Note: One needs to be aware of the value types associated with each attribute. The valueType property is only meant for reference.
 */
public enum AccessibilityFeatureAttribute: String, Identifiable, CaseIterable, Codable, Sendable, Comparable {
    case width
    case runningSlope
    case crossSlope
    /**
     Surface integrity-related attributes
     */
    case surfaceIntegrity
    case surfaceDisruption
    case heightFromGround
    case surfaceDisruptionArea
    case surfaceDisruptionLength
    /**
     - NOTE:
     Experimental attributes
     */
    case lidarDepth
    case latitudeDelta
    case longitudeDelta
    /**
    - NOTE:
        Legacy attributes for comparison with older data
     */
    case widthLegacy
    case runningSlopeLegacy
    case crossSlopeLegacy
    case widthFromImage
    case runningSlopeFromImage
    case crossSlopeFromImage
    /**
     Curb-ramp related attributes
     */
    case rampWidth
    case rampLength
    case rampRunningSlope
    case rampCrossSlope
    case leftFlareSlope
    case rightFlareSlope
    case counterSlope
    case turningSpaceWidth
    case turningSpaceLength
    case turningSpaceRunningSlope
    case turningSpaceCrossSlope
    
    public enum ValueType: Sendable, Codable, Equatable {
        case length
        case area
        case angle
        case number
        case flag
        case categorical(typeID: String)
    }

    public enum PrimitiveValue: Sendable, Codable, Equatable {
        case number(Double)
        case boolean(Bool)
        case string(String)

        /// The stable scalar representation used at the OSW tag boundary.
        /// Invalid floating-point values are omitted instead of being uploaded.
        public var oswTagValue: String? {
            switch self {
            case .number(let value):
                guard value.isFinite else { return nil }
                return String(
                    format: "%.2f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    value
                )
            case .boolean(let value):
                return value ? "yes" : "no"
            case .string(let value):
                return value
            }
        }
    }

    public struct NumericConstraints: Sendable, Equatable {
        public let minimum: Double?
        public let maximum: Double?

        public static let nonNegative = NumericConstraints(minimum: 0, maximum: nil)

        public init(minimum: Double?, maximum: Double?) {
            self.minimum = minimum
            self.maximum = maximum
        }

        public func contains(_ value: Double) -> Bool {
            if let minimum, value < minimum {
                return false
            }
            if let maximum, value > maximum {
                return false
            }
            return true
        }
    }
    
    public enum Value: Sendable, Codable, Equatable, CustomStringConvertible {
        case length(Measurement<UnitLength>)
        case area(Measurement<UnitArea>)
        case angle(Measurement<UnitAngle>)
        case number(Double)
        case flag(Bool)
        case categorical(AnyCategoricalValue)
        
        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case (.length(let l1), .length(let l2)):
                return l1 == l2
            case (.area(let a1), .area(let a2)):
                return a1 == a2
            case (.angle(let a1), .angle(let a2)):
                return a1 == a2
            case (.number(let n1), .number(let n2)):
                return n1 == n2
            case (.flag(let f1), .flag(let f2)):
                return f1 == f2
            case (.categorical(let c1), .categorical(let c2)):
                return c1 == c2
            default:
                return false
            }
        }
        
        public var description: String {
            switch self {
            case .length(let measurement):
                return String(format: "%.2f %@", measurement.value, measurement.unit.symbol)
            case .area(let measurement):
                return String(format: "%.2f %@", measurement.value, measurement.unit.symbol)
            case .angle(let measurement):
                return String(format: "%.2f %@", measurement.value, measurement.unit.symbol)
            case .number(let value):
                return String(format: "%.2f", value)
            case .flag(let value):
                return value ? "yes" : "no"
            case .categorical(let categoricalValue):
                return categoricalValue.rawValue
            }
        }
    }
    
    public struct Metadata {
        let id: Int
        let name: String
        let valueType: ValueType
        let numericConstraints: NumericConstraints?

        init(
            id: Int,
            name: String,
            valueType: ValueType,
            numericConstraints: NumericConstraints? = nil
        ) {
            self.id = id
            self.name = name
            self.valueType = valueType
            self.numericConstraints = numericConstraints
        }
    }
    
    private var metadata: Metadata {
        switch self {
        case .width:
            return Metadata(
                id: 10, name: "Width",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .runningSlope:
            return Metadata(
                id: 20, name: "Running Slope",
                valueType: .angle,
                numericConstraints: .nonNegative
            )
        case .crossSlope:
            return Metadata(
                id: 30, name: "Cross Slope",
                valueType: .angle,
                numericConstraints: .nonNegative
            )
        case .surfaceIntegrity:
            return Metadata(
                id: 40, name: "Surface Integrity",
                valueType: .categorical(typeID: SurfaceIntegrityStatus.typeID),
            )
        case .surfaceDisruption:
            return Metadata(
                id: 41, name: "Surface Disruption",
                valueType: .number,
                numericConstraints: .nonNegative
            )
        case .heightFromGround:
            return Metadata(
                id: 42, name: "Height from Ground",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .surfaceDisruptionArea:
            return Metadata(
                id: 43, name: "Surface Disruption Area",
                valueType: .area,
                numericConstraints: .nonNegative
            )
        case .surfaceDisruptionLength:
            return Metadata(
                id: 44, name: "Surface Disruption Length",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .lidarDepth:
            return Metadata(
                id: 50, name: "LiDAR Depth",
                valueType: .length,
            )
        case .latitudeDelta:
            return Metadata(
                id: 60, name: "Latitude Delta",
                valueType: .length,
            )
        case .longitudeDelta:
            return Metadata(
                id: 70, name: "Longitude Delta",
                valueType: .length,
            )
        case .widthLegacy:
            return Metadata(
                id: 15, name: "Width Legacy",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .runningSlopeLegacy:
            return Metadata(
                id: 25, name: "Running Slope Legacy",
                valueType: .angle,
            )
        case .crossSlopeLegacy:
            return Metadata(
                id: 35, name: "Cross Slope Legacy",
                valueType: .angle,
            )
        case .widthFromImage:
            return Metadata(
                id: 16, name: "Width from Image",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .runningSlopeFromImage:
            return Metadata(
                id: 26, name: "Running Slope from Image",
                valueType: .angle,
            )
        case .crossSlopeFromImage:
            return Metadata(
                id: 36, name: "Cross Slope from Image",
                valueType: .angle,
            )
        case .rampWidth:
            return Metadata(
                id: 110, name: "Ramp Width",
                valueType: .length,
            )
        case .rampLength:
            return Metadata(
                id: 120, name: "Ramp Length",
                valueType: .length,
            )
        case .rampRunningSlope:
            return Metadata(
                id: 130, name: "Ramp Running Slope",
                valueType: .angle,
            )
        case .rampCrossSlope:
            return Metadata(
                id: 140, name: "Ramp Cross Slope",
                valueType: .angle,
            )
        case .leftFlareSlope:
            return Metadata(
                id: 141, name: "Left Flare Slope",
                valueType: .angle,
            )
        case .rightFlareSlope:
            return Metadata(
                id: 142, name: "Right Flare Slope",
                valueType: .angle,
            )
        case .counterSlope:
            return Metadata(
                id: 150, name: "Counter Slope",
                valueType: .angle,
            )
        case .turningSpaceWidth:
            return Metadata(
                id: 160, name: "Turning Space Width",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .turningSpaceLength:
            return Metadata(
                id: 170, name: "Turning Space Length",
                valueType: .length,
                numericConstraints: .nonNegative
            )
        case .turningSpaceRunningSlope:
            return Metadata(
                id: 180, name: "Turning Space Running Slope",
                valueType: .angle,
            )
        case .turningSpaceCrossSlope:
            return Metadata(
                id: 190, name: "Turning Space Cross Slope",
                valueType: .angle,
            )
        }
    }
    
    public var id: Int {
        return metadata.id
    }
    
    public var name: String {
        return metadata.name
    }
    
    public var canonicalUnit: Dimension? {
        switch valueType {
        case .length:
            return PointNMapConstants.MeasurementUnits.canonicalLengthUnit
        case .area:
            return PointNMapConstants.MeasurementUnits.canonicalAreaUnit
        case .angle:
            return PointNMapConstants.MeasurementUnits.canonicalAngleUnit
        case .number, .flag, .categorical:
            return nil
        }
    }
    
    public var valueType: ValueType {
        return metadata.valueType
    }

    public var numericConstraints: NumericConstraints? {
        return metadata.numericConstraints
    }
    
    public var displayName: String {
        displayName(using: .default)
    }

    public func unit(using preferences: MeasurementUnitPreferences) -> Dimension? {
        switch valueType {
        case .length:
            return preferences.length.unit
        case .area:
            return preferences.area.unit
        case .angle:
            return preferences.angle.unit
        case .number, .flag, .categorical:
            return nil
        }
    }

    public func displayName(using preferences: MeasurementUnitPreferences) -> String {
        guard let unit = unit(using: preferences) else { return name }
        return "\(name) (\(unit.symbol))"
    }
    
    public static func < (lhs: AccessibilityFeatureAttribute, rhs: AccessibilityFeatureAttribute) -> Bool {
        return lhs.id < rhs.id
    }
}

public extension AccessibilityFeatureAttribute.Value {
    var valueType: AccessibilityFeatureAttribute.ValueType {
        switch self {
        case .length: return .length
        case .area: return .area
        case .angle: return .angle
        case .number: return .number
        case .flag: return .flag
        case .categorical(let categoricalValue): return .categorical(typeID: categoricalValue.typeID)
        }
    }
}

/**
 Extensions for AccessibilityFeatureAttribute to provide expected value types,
 */
public extension AccessibilityFeatureAttribute {
//    func isCompatible(with value: Value) -> Bool {
//        return self.valueType == value.valueType
//    }
    func isCompatible(with value: Value) -> Bool {
        switch (self.valueType, value) {
        case (.length, .length),
             (.area, .area),
             (.angle, .angle),
            (.number, .number),
             (.flag, .flag):
            return true
        case (.categorical(let expectedID), .categorical(let cat)):
            return cat.typeID == expectedID
        default:
            return false
        }
    }

    func validate(_ value: Value) throws {
        guard isCompatible(with: value) else {
            throw AccessibilityFeatureError.attributeValueMismatch(attribute: self, value: value)
        }
        guard let numericValue = value.canonicalNumericValue else {
            return
        }
        guard numericValue.isFinite else {
            throw AccessibilityFeatureError.attributeValueNotFinite(
                attribute: self,
                value: numericValue
            )
        }
        guard numericConstraints?.contains(numericValue) ?? true else {
            throw AccessibilityFeatureError.attributeValueOutOfRange(
                attribute: self,
                value: numericValue,
                minimum: numericConstraints?.minimum,
                maximum: numericConstraints?.maximum
            )
        }
    }
}

/**
 Extension to convert AccessibilityFeatureAttribute.Value to and from primitive types.
 */
public extension AccessibilityFeatureAttribute.Value {
    func convertedForDisplay(using preferences: MeasurementUnitPreferences) -> Self {
        switch self {
        case .length(let measurement):
            return .length(measurement.converted(to: preferences.length.unit))
        case .area(let measurement):
            return .area(measurement.converted(to: preferences.area.unit))
        case .angle(let measurement):
            return .angle(measurement.converted(to: preferences.angle.unit))
        case .number, .flag, .categorical:
            return self
        }
    }

    func displayNumericValue(using preferences: MeasurementUnitPreferences) -> Double? {
        switch convertedForDisplay(using: preferences) {
        case .length(let measurement): return measurement.value
        case .area(let measurement): return measurement.value
        case .angle(let measurement): return measurement.value
        case .number(let value): return value
        case .flag, .categorical: return nil
        }
    }

    internal func roundedForFinalAttribute() -> Self {
        func rounded(_ value: Double) -> Double {
            guard value.isFinite else { return value }
            let scale = pow(10.0, Double(PointNMapConstants.finalAttributePrecision))
            let scaledValue = value * scale
            guard scale.isFinite, scale != 0, scaledValue.isFinite else {
                return value
            }
            return scaledValue.rounded() / scale
        }

        switch self {
        case .length(let measurement):
            let unit = PointNMapConstants.MeasurementUnits.canonicalLengthUnit
            let value = measurement.converted(to: unit).value
            return .length(Measurement(value: rounded(value), unit: unit))
        case .area(let measurement):
            let unit = PointNMapConstants.MeasurementUnits.canonicalAreaUnit
            let value = measurement.converted(to: unit).value
            return .area(Measurement(value: rounded(value), unit: unit))
        case .angle(let measurement):
            let unit = PointNMapConstants.MeasurementUnits.canonicalAngleUnit
            let value = measurement.converted(to: unit).value
            return .angle(Measurement(value: rounded(value), unit: unit))
        case .number(let value):
            return .number(rounded(value))
        case .flag, .categorical:
            return self
        }
    }

    var canonicalNumericValue: Double? {
        switch self {
        case .length(let measurement):
            return measurement.converted(to: PointNMapConstants.MeasurementUnits.canonicalLengthUnit).value
        case .area(let measurement):
            return measurement.converted(to: PointNMapConstants.MeasurementUnits.canonicalAreaUnit).value
        case .angle(let measurement):
            return measurement.converted(to: PointNMapConstants.MeasurementUnits.canonicalAngleUnit).value
        case .number(let value):
            return value
        case .flag:
            return nil
        case .categorical:
            return nil
        }
    }

    var primitiveValue: AccessibilityFeatureAttribute.PrimitiveValue {
        switch self {
        case .length(let measurement):
            return .number(measurement.converted(to: PointNMapConstants.MeasurementUnits.canonicalLengthUnit).value)
        case .area(let measurement):
            return .number(measurement.converted(to: PointNMapConstants.MeasurementUnits.canonicalAreaUnit).value)
        case .angle(let measurement):
            return .number(measurement.converted(to: PointNMapConstants.MeasurementUnits.canonicalAngleUnit).value)
        case .number(let value):
            return .number(value)
        case .flag(let value):
            return .boolean(value)
        case .categorical(let value):
            return .string(value.rawValue)
        }
    }
}

public extension AccessibilityFeatureAttribute {
    func value(from double: Double) -> Value? {
        value(from: double, using: .default)
    }

    func value(from double: Double, using preferences: MeasurementUnitPreferences) -> Value? {
        switch self.valueType {
        case .length:
            return .length(Measurement(value: double, unit: preferences.length.unit))
        case .area:
            return .area(Measurement(value: double, unit: preferences.area.unit))
        case .angle:
            return .angle(Measurement(value: double, unit: preferences.angle.unit))
        case .number:
            return .number(double)
        case .flag:
            return nil // Flags cannot be represented as doubles
        case .categorical:
            return nil
        }
    }
    
    func value(from bool: Bool) -> Value? {
        switch self.valueType {
        case .flag:
            return .flag(bool)
        default:
            return nil // Only flags can be represented as booleans
        }
    }
    
    func value<T: FeatureCategorical>(from categorical: T) -> Value? {
        switch self.valueType {
        case .categorical(let expectedID):
            if T.typeID == expectedID {
                return .categorical(AnyCategoricalValue(categorical))
            } else {
                return nil // Categorical type ID does not match
            }
        default:
            return nil // Only categorical attributes can be represented as categorical values
        }
    }
    
    func value(from categoricalRawValue: String) -> Value? {
        switch self.valueType {
        case .categorical(let expectedID):
            switch expectedID {
            case SurfaceIntegrityStatus.typeID:
                if let categoricalValue = SurfaceIntegrityStatus(rawValue: categoricalRawValue) {
                    return .categorical(AnyCategoricalValue(categoricalValue))
                } else {
                    return nil // Invalid categorical raw value for Surface Integrity
                }
            default:
                guard let decoded = CategoricalAttributeRegistry.decodeToCategoricalValue(
                    typeID: expectedID,
                    raw: categoricalRawValue
                ) else {
                    return nil
                }
                return .categorical(decoded)
            }
        default:
            return nil // Only categorical attributes can be represented as categorical values
        }
    }
    
    func categoricalOptions() -> [AnyCategoricalValue] {
        guard case .categorical(let typeID) = self.valueType else {
            return []
        }
        if typeID == SurfaceIntegrityStatus.typeID {
            let options = SurfaceIntegrityStatus.allCases.map { AnyCategoricalValue($0) }
            return options
        }
        let options = CategoricalAttributeRegistry.cases(for: typeID) ?? []
        return options
    }
    
    func defaultValue() -> Value? {
        switch self.valueType {
        case .length:
            return .length(Measurement(value: 0.0, unit: .meters))
        case .area:
            return .area(Measurement(value: 0.0, unit: .squareMeters))
        case .angle:
            return .angle(Measurement(value: 0.0, unit: .degrees))
        case .number:
            return .number(0.0)
        case .flag:
            return .flag(false)
        case .categorical(_):
            return nil
        }
    }
}
