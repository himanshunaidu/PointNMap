//
//  AnnotationFeatureDetailView.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/28/25.
//

import SwiftUI
import Combine

public func AnnotationFeatureDetailLocationFormatter() -> NumberFormatter {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.maximumFractionDigits = 7
    nf.minimumFractionDigits = 7
    return nf
}

public enum AnnotationFeatureDetailViewConstants {
    public enum Texts {
        /// Alert texts
        public static let statusAlertTitleKey: String = "Error"
        public static let statusAlertDismissAlertSuffixKey: String = "Press OK to dismiss this alert."
        public static let statusAlertDismissButtonKey: String = "OK"
        
        /// Is Existing
        public static let isExistingTitle: String = "Is this an existing feature?"
        
        /// Invalid
        public static let invalidTextKey: String = "Invalid"
    }
    
    public enum Images {
        /// Alert images
        public static let statusAlertImageNameKey: String = "exclamationmark.triangle.fill"
    }
}

func annotationFeatureDetailNumericEstimate(
    _ calculatedValue: AccessibilityFeatureAttribute.Value?
) -> Double? {
    guard let estimate = calculatedValue?.toDouble(), estimate.isFinite else {
        return nil
    }
    return estimate
}

func annotationFeatureDetailCanUseEstimate(
    attribute: AccessibilityFeatureAttribute,
    currentValue: AccessibilityFeatureAttribute.Value?,
    calculatedValue: AccessibilityFeatureAttribute.Value?
) -> Bool {
    guard let calculatedValue,
          annotationFeatureDetailNumericEstimate(calculatedValue) != nil,
          (try? attribute.validate(calculatedValue)) != nil else {
        return false
    }
    return currentValue?.roundedForFinalAttribute()
        != calculatedValue.roundedForFinalAttribute()
}

/**
    A view that displays detailed information about an accessibility feature annotation.
    Sub-view of the `AnnotationView`.
 */
public struct AnnotationFeatureDetailViewBase<
    Feature: EditableAccessibilityFeatureProtocol,
    LocationSection: View
    >: View {
    
    public enum AnnotationFeatureDetailViewError: Error, LocalizedError {
        case invalidAttributeValue(attribute: AccessibilityFeatureAttribute, message: String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidAttributeValue(let attribute, let message):
                return "Invalid value for \(attribute.displayName): \(message)"
            }
        }
    }
    
    public struct AttributeErrorStatus {
        public var isError: Bool
        public var errorMessage: String
        
        public init(isError: Bool, errorMessage: String) {
            self.isError = isError
            self.errorMessage = errorMessage
        }
    }
    
    public class StatusViewModel: ObservableObject {
        @Published public var attributeStatusMap: [AccessibilityFeatureAttribute: AttributeErrorStatus] = [:]
        
        public func configure(accessibilityFeature: Feature) {
            let attributes = accessibilityFeature.accessibilityFeatureClass.kind.attributes
            var attributeStatusMap: [AccessibilityFeatureAttribute: AttributeErrorStatus] = [:]
            attributes.forEach {
                let initialStatus = AttributeErrorStatus(isError: false, errorMessage: "")
                attributeStatusMap[$0] = initialStatus
            }
            self.attributeStatusMap = attributeStatusMap
        }
        
        public func updateAttributeStatus(
            for attribute: AccessibilityFeatureAttribute,
            isError: Bool,
            errorMessage: String
        ) {
            if let _ = attributeStatusMap[attribute] {
                attributeStatusMap[attribute]?.isError = isError
                attributeStatusMap[attribute]?.errorMessage = errorMessage
            }
        }
    }
    
    public var accessibilityFeature: Feature
    public let title: String
    private let locationSection: (Feature) -> LocationSection
    private let locationFormatter = AnnotationFeatureDetailLocationFormatter()
    
    @StateObject private var statusViewModel = AnnotationFeatureDetailViewBase.StatusViewModel()
    @FocusState private var focusedField: AccessibilityFeatureAttribute?
    /// Note: Fields such as pickers don't have built-in ways to update their UI based on user input. Hence we need to trigger a refresh manually when their value changes.
    @State private var pickerRefreshTrigger: Int = 0
    @State private var numericRefreshTrigger: Int = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    public init(
        accessibilityFeature: Feature,
        title: String,
        @ViewBuilder locationSection: @escaping (Feature) -> LocationSection
    ) {
        self.accessibilityFeature = accessibilityFeature
        self.title = title
        self.locationSection = locationSection
    }
    
    public var body: some View {
        VStack {
            Text(title)
                .font(.headline)
                .padding()
            
            Form {
                Section(header: Text(AnnotationViewBaseConstants.Texts.featureDetailViewIdKey)) {
                    Text(accessibilityFeature.id.uuidString)
                        .foregroundStyle(.secondary)
                }
                
                /**
                 Location Section
                 */
                locationSection(accessibilityFeature)
                
                /**
                 The Attributes Section
                 Instead of using a ForEach loop, we manually list out each attribute to have more control over the layout and presentation.
                 This allows us to customize the display for each attribute type as needed.
                 There isn't a large number of attributes, so this approach is manageable and provides better clarity.
                 */
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.width))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.width.displayName)) {
                        numberTextFieldView(attribute: .width)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.runningSlope))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.runningSlope.displayName)) {
                        numberTextFieldView(attribute: .runningSlope)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.crossSlope))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.crossSlope.displayName)) {
                        numberTextFieldView(attribute: .crossSlope)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.surfaceIntegrity))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.surfaceIntegrity.displayName)) {
                        pickerView(attribute: .surfaceIntegrity)
                            .focused($focusedField, equals: .surfaceIntegrity)
                            .id(pickerRefreshTrigger) // Refresh the Picker view when its value changes
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.surfaceDisruption)) {
                    Section(header: Text(AccessibilityFeatureAttribute.surfaceDisruption.displayName)) {
                        numberTextFieldView(attribute: .surfaceDisruption)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.heightFromGround)) {
                    Section(header: Text(AccessibilityFeatureAttribute.heightFromGround.displayName)) {
                        numberTextFieldView(attribute: .heightFromGround)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.surfaceDisruptionArea)) {
                    Section(header: Text(AccessibilityFeatureAttribute.surfaceDisruptionArea.displayName)) {
                        numberTextFieldView(attribute: .surfaceDisruptionArea)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.surfaceDisruptionLength)) {
                    Section(header: Text(AccessibilityFeatureAttribute.surfaceDisruptionLength.displayName)) {
                        numberTextFieldView(attribute: .surfaceDisruptionLength)
                    }
                }
                
                /// Experimental Attributes Section
                if (accessibilityFeature.accessibilityFeatureClass.kind.experimentalAttributes.contains(.lidarDepth)) {
                    Section(header: Text(AccessibilityFeatureAttribute.lidarDepth.displayName)) {
                        numberTextView(attribute: .lidarDepth)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.experimentalAttributes.contains(.latitudeDelta)) {
                    Section(header: Text(AccessibilityFeatureAttribute.latitudeDelta.displayName)) {
                        numberTextView(attribute: .latitudeDelta)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.experimentalAttributes.contains(.longitudeDelta)) {
                    Section(header: Text(AccessibilityFeatureAttribute.longitudeDelta.displayName)) {
                        numberTextView(attribute: .longitudeDelta)
                    }
                }
                
                /// Legacy Attributes Section
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.widthLegacy))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.widthLegacy.displayName)) {
                        numberTextFieldView(attribute: .widthLegacy)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.runningSlopeLegacy))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.runningSlopeLegacy.displayName)) {
                        numberTextFieldView(attribute: .runningSlopeLegacy)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.crossSlopeLegacy))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.crossSlopeLegacy.displayName)) {
                        numberTextFieldView(attribute: .crossSlopeLegacy)
                    }
                }
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.widthFromImage))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.widthFromImage.displayName)) {
                        numberTextFieldView(attribute: .widthFromImage)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.runningSlopeFromImage))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.runningSlopeFromImage.displayName)) {
                        numberTextFieldView(attribute: .runningSlopeFromImage)
                    }
                }
                
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.crossSlopeFromImage))
                {
                    Section(header: Text(AccessibilityFeatureAttribute.crossSlopeFromImage.displayName)) {
                        numberTextFieldView(attribute: .crossSlopeFromImage)
                    }
                }
                
                /// Curb Ramp Section
                /// TODO: Find a more generic way to handle this in the future.
                // ramp width
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.rampWidth)) {
                    Section(header: Text(AccessibilityFeatureAttribute.rampWidth.displayName)) {
                        numberTextFieldView(attribute: .rampWidth)
                    }
                }
                // ramp length
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.rampLength)) {
                    Section(header: Text(AccessibilityFeatureAttribute.rampLength.displayName)) {
                        numberTextFieldView(attribute: .rampLength)
                    }
                }
                // ramp running slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.rampRunningSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.rampRunningSlope.displayName)) {
                        numberTextFieldView(attribute: .rampRunningSlope)
                    }
                }
                // ramp cross slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.rampCrossSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.rampCrossSlope.displayName)) {
                        numberTextFieldView(attribute: .rampCrossSlope)
                    }
                }
                // left flare slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.leftFlareSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.leftFlareSlope.displayName)) {
                        numberTextFieldView(attribute: .leftFlareSlope)
                    }
                }
                // right flare slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.rightFlareSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.rightFlareSlope.displayName)) {
                        numberTextFieldView(attribute: .rightFlareSlope)
                    }
                }
                // counter slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.counterSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.counterSlope.displayName)) {
                        numberTextFieldView(attribute: .counterSlope)
                    }
                }
                // turning space width
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.turningSpaceWidth)) {
                    Section(header: Text(AccessibilityFeatureAttribute.turningSpaceWidth.displayName)) {
                        numberTextFieldView(attribute: .turningSpaceWidth)
                    }
                }
                // turning space length
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.turningSpaceLength)) {
                    Section(header: Text(AccessibilityFeatureAttribute.turningSpaceLength.displayName)) {
                        numberTextFieldView(attribute: .turningSpaceLength)
                    }
                }
                // turning space running slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.turningSpaceRunningSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.turningSpaceRunningSlope.displayName)) {
                        numberTextFieldView(attribute: .turningSpaceRunningSlope)
                    }
                }
                // turning space cross slope
                if (accessibilityFeature.accessibilityFeatureClass.kind.attributes.contains(.turningSpaceCrossSlope)) {
                    Section(header: Text(AccessibilityFeatureAttribute.turningSpaceCrossSlope.displayName)) {
                        numberTextFieldView(attribute: .turningSpaceCrossSlope)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            self.statusViewModel.configure(accessibilityFeature: accessibilityFeature)
            focusedField = nil
        }
    }
    
    @ViewBuilder
    private func numberTextFieldView(attribute: AccessibilityFeatureAttribute) -> some View {
        let attributeStatus = statusViewModel.attributeStatusMap[attribute] ?? .init(isError: false, errorMessage: "")
        let currentValue = accessibilityFeature.attributeValues[attribute] ?? nil
        let calculatedValue = accessibilityFeature.calculatedAttributeValues[attribute] ?? nil
        let appEstimate = annotationFeatureDetailNumericEstimate(calculatedValue)
        let canUseAppEstimate = annotationFeatureDetailCanUseEstimate(
            attribute: attribute,
            currentValue: currentValue,
            calculatedValue: calculatedValue
        )
        let estimateLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        let _ = numericRefreshTrigger

        VStack(alignment: .leading, spacing: 8) {
            if (attributeStatus.isError) {
                /// A red colored error message
                HStack {
                    Label(
                        attributeStatus.errorMessage,
                        systemImage: AnnotationFeatureDetailViewConstants.Images.statusAlertImageNameKey
                    )
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                }
            }

            numberTextField(attribute: attribute)

            estimateLayout {
                appEstimateView(appEstimate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                useAppEstimateButton(
                    attribute: attribute,
                    calculatedValue: calculatedValue,
                    canUseAppEstimate: canUseAppEstimate
                )
            }
        }
    }

    private func numberTextField(attribute: AccessibilityFeatureAttribute) -> some View {
        TextField(
            attribute.displayName,
            value: Binding(
                get: {
                    guard let attributeValue = accessibilityFeature.attributeValues[attribute],
                          let attributeValue,
                          let attributeBindableValue = attributeValue.toDouble() else {
                        return 0.0
                    }
                    return attributeBindableValue
                },
                set: { newValue in
                    do {
                        guard let newAttributeValue = attribute.value(from: newValue) else {
                            return
                        }
                        try accessibilityFeature.setAttributeValue(newAttributeValue, for: attribute)
                        numericRefreshTrigger += 1
                    } catch {
                        setAttributeStatusErrorText(for: attribute, message: "\(error.localizedDescription)")
                        numericRefreshTrigger += 1
                    }
                }
            ),
            format: .number.precision(
                .fractionLength(0...PointNMapConstants.finalAttributePrecision)
            )
        )
        .focused($focusedField, equals: attribute)
        .textFieldStyle(.roundedBorder)
        .keyboardType(.numbersAndPunctuation)
        .submitLabel(.done)
        .onSubmit {
            focusedField = nil
        }
        .accessibilityLabel(Text(attribute.displayName))
    }

    @ViewBuilder
    private func appEstimateView(_ appEstimate: Double?) -> some View {
        if let appEstimate {
            Text(
                "App estimate: \(appEstimate, format: .number.precision(.fractionLength(0...PointNMapConstants.finalAttributePrecision)))",
                bundle: #bundle,
                comment: "The numeric attribute value estimated by the app"
            )
            .foregroundStyle(.secondary)
        } else {
            Text(
                "App estimate: Unavailable",
                bundle: #bundle,
                comment: "Shown when the app could not estimate a numeric attribute value"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func useAppEstimateButton(
        attribute: AccessibilityFeatureAttribute,
        calculatedValue: AccessibilityFeatureAttribute.Value?,
        canUseAppEstimate: Bool
    ) -> some View {
        Button {
            guard let calculatedValue else { return }

            do {
                try accessibilityFeature.setAttributeValue(calculatedValue, for: attribute)
                numericRefreshTrigger += 1
            } catch {
                setAttributeStatusErrorText(for: attribute, message: "\(error.localizedDescription)")
            }
        } label: {
//            Label {
//                Text(
//                    "Use app estimate",
//                    bundle: #bundle,
//                    comment: "Button that restores an app-estimated numeric attribute value"
//                )
//            } icon: {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.title2)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
//            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(!canUseAppEstimate)
        .accessibilityLabel(Text("Use app estimate", bundle: #bundle))
        .accessibilityHint(
            Text(
                "Replaces the edited value with the value estimated by the app",
                bundle: #bundle
            )
        )
    }
    
    @ViewBuilder
    private func numberTextView(attribute: AccessibilityFeatureAttribute) -> some View {
        let attributeStatus = statusViewModel.attributeStatusMap[attribute] ?? .init(isError: false, errorMessage: "")
        let valueToDisplay: String = {
            guard let attributeValue = accessibilityFeature.experimentalAttributeValues[attribute],
                  let attributeValue,
                  let attributeBindableValue = attributeValue.toDouble() else {
                return AnnotationFeatureDetailViewConstants.Texts.invalidTextKey
            }
            return String(attributeBindableValue)
        }()
        VStack {
            if (attributeStatus.isError) {
                /// A red colored error message
                HStack {
                    Label(
                        attributeStatus.errorMessage,
                        systemImage: AnnotationFeatureDetailViewConstants.Images.statusAlertImageNameKey
                    )
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                }
            }
            Text(valueToDisplay)
        }
    }
    
    @ViewBuilder
    private func toggleView(attribute: AccessibilityFeatureAttribute) -> some View {
        Toggle(
            isOn: Binding(
                get: {
                    guard let attributeValue = accessibilityFeature.attributeValues[attribute],
                          let attributeValue,
                          let attributeBindableValue = attributeValue.toBool() else {
                        return false
                    }
                    return attributeBindableValue
                },
                set: { newValue in
                    do {
                        let newBoolValue = Bool(newValue)
                        guard let newAttributeValue = attribute.value(from: newBoolValue) else {
                            return
                        }
                        try accessibilityFeature.setAttributeValue(newAttributeValue, for: attribute)
                    } catch {
                        setAttributeStatusErrorText(for: attribute, message: "\(error.localizedDescription)")
                    }
                }
            )
        ) {
            Text(attribute.displayName)
        }
    }
    
    @ViewBuilder
    private func pickerView(attribute: AccessibilityFeatureAttribute) -> some View {
        Picker(
            attribute.displayName,
            selection: Binding<AnyCategoricalValue?>(
                get: {
                    guard case .categorical(let category) = accessibilityFeature.attributeValues[attribute] else {
                        return attribute.categoricalOptions().first
                    }
                    return category
                },
                set: { newValue in
                    guard let newValue else { return }
                    do {
                        let newCategoricalValue: AccessibilityFeatureAttribute.Value = .categorical(newValue)
                        try accessibilityFeature.setAttributeValue(newCategoricalValue, for: attribute)
                        pickerRefreshTrigger += 1 // Trigger a refresh to update the Picker's displayed value
                    } catch {
                        setAttributeStatusErrorText(for: attribute, message: "\(error.localizedDescription)")
                    }
                }
        )) {
            ForEach(attribute.categoricalOptions(), id: \.self) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.menu)
    }
    
    private func setAttributeStatusErrorText(
        for attribute: AccessibilityFeatureAttribute, message: String
    ) {
        statusViewModel.updateAttributeStatus(for: attribute, isError: true, errorMessage: message)
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
                statusViewModel.updateAttributeStatus(for: attribute, isError: false, errorMessage: "")
            } catch {
                print("Failed to reset attribute error status: \(error.localizedDescription)")
            }
        }
    }
}
