import Foundation

public enum LengthUnitChoice: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case meters
    case feet
    case inches

    public var id: String { rawValue }

    public var unit: UnitLength {
        switch self {
        case .meters: return .meters
        case .feet: return .feet
        case .inches: return .inches
        }
    }

    public var displayName: String {
        switch self {
        case .meters: return "Meters"
        case .feet: return "Feet"
        case .inches: return "Inches"
        }
    }

    public var symbol: String { unit.symbol }
}

public enum AreaUnitChoice: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case squareMeters
    case squareFeet
    case squareInches

    public var id: String { rawValue }

    public var unit: UnitArea {
        switch self {
        case .squareMeters: return .squareMeters
        case .squareFeet: return .squareFeet
        case .squareInches: return .squareInches
        }
    }

    public var displayName: String {
        switch self {
        case .squareMeters: return "Square meters"
        case .squareFeet: return "Square feet"
        case .squareInches: return "Square inches"
        }
    }

    public var symbol: String { unit.symbol }
}

public enum AngleUnitChoice: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case degrees
    case radians

    public var id: String { rawValue }

    public var unit: UnitAngle {
        switch self {
        case .degrees: return .degrees
        case .radians: return .radians
        }
    }

    public var displayName: String {
        switch self {
        case .degrees: return "Degrees"
        case .radians: return "Radians"
        }
    }

    public var symbol: String { unit.symbol }
}

public struct MeasurementUnitPreferences: Sendable, Codable, Equatable {
    public let length: LengthUnitChoice
    public let area: AreaUnitChoice
    public let angle: AngleUnitChoice

    public init(
        length: LengthUnitChoice,
        area: AreaUnitChoice,
        angle: AngleUnitChoice
    ) {
        self.length = length
        self.area = area
        self.angle = angle
    }

    public static let `default` = MeasurementUnitPreferences(
        length: PointNMapConstants.MeasurementUnits.defaultLengthChoice,
        area: PointNMapConstants.MeasurementUnits.defaultAreaChoice,
        angle: PointNMapConstants.MeasurementUnits.defaultAngleChoice
    )
}
