//
//  AnnotationViewBase.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/10/25.
//

import SwiftUI
import Combine
import TipKit
import CoreLocation
import simd

enum AnnotationViewBaseConstants {
    enum Texts {
        static let annotationViewTitle = "Annotation"
        
        static let currentClassPrefixText = "Selected class"
        static let finishText = "Finish"
        static let nextText = "Next"
        
        static let selectObjectText = "Select an object"
        static let allText = "All"
        static let individualText = "Individual"
        static let detailsText = "Details"
        static let keepText = "Keep"
        static let discardText = "Discard"
        static let fromGroupText = "Group"
        static let individualChoiceText = "Override"
        static let useGroupDecisionText = "Use group decision"
        static let reviewRulePrefixText = "Review rule:"
        static let sidewalkReviewRuleText = "Keep if the highlighted sidewalk mostly matches the real sidewalk. Small gaps are okay; large missing areas or major spillover are not."
        
        static let loadingPageText = "Loading. Please wait..."
        
        /// Feature Detail View Text
        static let featureDetailViewTitle = "Feature Details"
        static let featureDetailViewIdKey = "ID"
        static let featureDetailViewLocationKey = "Location"
        static let featureDetailNotAvailableText = "Not Available"
        
        /// Alert texts
        static let managerStatusAlertTitleKey = "Error"
        static let managerStatusAlertDismissButtonKey = "OK"
        static let managerStatusAlertMessageDismissScreenSuffixKey = "Press OK to close this screen."
        static let managerStatusAlertMessageDismissAlertSuffixKey = "Press OK to dismiss this alert."
        static let apiChangesetUploadStatusAlertTitleKey = "Upload Error"
        static let apiChangesetUploadStatusAlertDismissButtonKey = "OK"
        static let apiChangesetUploadStatusAlertGenericMessageKey = "Failed to upload features. Press OK to dismiss this alert."
        static let apiChangesetUploadStatusAlertMessageSuffixKey = " feature(s) failed to upload. Press OK to dismiss this alert."
        
        /// SelectObjectInfoTip
        static let selectFeatureInfoTipTitle = "Select a Feature"
        static let selectFeatureInfoTipMessage = "Please select the individual feature that you want to annotate"
        static let selectFeatureInfoTipLearnMoreButtonTitle = "Learn More"
        
        /// SelectObjectInfoLearnMoreSheetView
        static let selectFeatureInfoLearnMoreSheetTitle = "Annotating an Individual Feature"
        static let selectFeatureInfoLearnMoreSheetMessage = """
        For each type of accessibility feature, the app can identify multiple feature instances within the same image. 
        
        **Select All**: Default option. You can annotate all features of a particular type together.
        
        **Individual**: You can select a particular feature from the dropdown menu if you wish to provide specific annotations for an individual feature.
        
        **Ellipsis [...]**: For each feature, you can also view its details by tapping the ellipsis button next to the dropdown menu.
        """
    }
    
    enum Images {
        static let checkIcon = "checkmark"
        static let ellipsisIcon = "ellipsis"
        static let infoIcon = "info.circle"
        static let closeIcon = "xmark"
        static let errorIcon = "exclamationmark.triangle"
    }
}

enum AnnotationViewBaseError: Error, LocalizedError {
    case classIndexOutofBounds
    case instanceIndexOutofBounds
    case invalidCaptureDataRecord
    case managerConfigurationFailed
    case authenticationError
    case workspaceConfigurationFailed
    case attributeEstimationFailed(Error)
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .classIndexOutofBounds:
            return "The Current Class is not in the list."
        case .instanceIndexOutofBounds:
            return "Exceeded the number of instances for the current class."
        case .invalidCaptureDataRecord:
            return "The Current Capture is invalid."
        case .managerConfigurationFailed:
            return "Annotation Configuration failed"
        case .authenticationError:
            return "Authentication error. Please log in again."
        case .workspaceConfigurationFailed:
            return "Workspace configuration failed. Please check your workspace settings."
        case .attributeEstimationFailed(let error):
            return "Some Attribute Estimation calculations failed. They may be ignored. \nError: \(error.localizedDescription)"
        case .uploadFailed:
            return "Failed to upload annotations."
        }
    }
}

@available(iOS 17.0, *)
struct SelectFeatureInfoTipBase: Tip {
    
    var title: Text {
        Text(AnnotationViewBaseConstants.Texts.selectFeatureInfoTipTitle)
    }
    var message: Text? {
        Text(AnnotationViewBaseConstants.Texts.selectFeatureInfoTipMessage)
    }
    var image: Image? {
        Image(systemName: AnnotationViewBaseConstants.Images.infoIcon)
            .resizable()
    }
    var actions: [Action] {
        // Define a learn more button.
        Action(
            id: AnnotationViewBaseConstants.Texts.selectFeatureInfoTipLearnMoreButtonTitle,
            title: AnnotationViewBaseConstants.Texts.selectFeatureInfoTipLearnMoreButtonTitle
        )
    }
}

class AnnotationFeatureClassSelectionViewBaseModel: ObservableObject {
    @Published var currentIndex: Int? = nil
    @Published var currentClass: AccessibilityFeatureClass? = nil
    @Published var selectedAnnotationOption: AnnotationOption = .classOption(.default)
    
    func setCurrent(index: Int, classes: [AccessibilityFeatureClass]) throws {
        guard index < classes.count else {
            throw AnnotationViewBaseError.classIndexOutofBounds
        }
        self.currentIndex = index
        self.currentClass = classes[index]
    }
    
    func setOption(option: AnnotationOption) {
        self.selectedAnnotationOption = option
    }
}

enum AnnotationViewBaseReviewScope: Hashable {
    case all
    case individual
}

struct AnnotationViewBaseDecisionSummary: Equatable {
    let keptCount: Int
    let discardedCount: Int
    let exceptionCount: Int
}

class AnnotationFeatureSelectionViewBaseModel: ObservableObject {
    @Published var instances: [EditableAccessibilityFeature] = []
    @Published var currentIndex: Int? = nil
    @Published var currentFeature: EditableAccessibilityFeature? = nil
    @Published var reviewScope: AnnotationViewBaseReviewScope = .all

    private var lastSelectedFeatureID: UUID?

    var groupDecision: AnnotationDecision {
        instances.first?.groupAnnotationDecision ?? .keep
    }

    var decisionSummary: AnnotationViewBaseDecisionSummary {
        instances.reduce(
            into: AnnotationViewBaseDecisionSummary(
                keptCount: 0,
                discardedCount: 0,
                exceptionCount: 0
            )
        ) { summary, feature in
            switch feature.effectiveAnnotationDecision {
            case .keep:
                summary = AnnotationViewBaseDecisionSummary(
                    keptCount: summary.keptCount + 1,
                    discardedCount: summary.discardedCount,
                    exceptionCount: summary.exceptionCount
                        + (feature.isAnnotationDecisionException ? 1 : 0)
                )
            case .discard:
                summary = AnnotationViewBaseDecisionSummary(
                    keptCount: summary.keptCount,
                    discardedCount: summary.discardedCount + 1,
                    exceptionCount: summary.exceptionCount
                        + (feature.isAnnotationDecisionException ? 1 : 0)
                )
            }
        }
    }
    
    func setInstances(_ instances: [EditableAccessibilityFeature], currentClass: AccessibilityFeatureClass) throws {
        self.instances = instances
        lastSelectedFeatureID = instances.first?.id
        if currentClass.kind.isUniquePerCapture {
            reviewScope = .individual
            try setIndex(index: instances.isEmpty ? nil : 0)
        } else {
            reviewScope = .all
            try setIndex(index: nil)
        }
    }
    
    func setIndex(index: Int?) throws {
        guard let index = index else {
            self.currentIndex = nil
            self.currentFeature = nil
            return
        }
        guard index < instances.count else {
            throw AnnotationViewBaseError.instanceIndexOutofBounds
        }
        self.currentIndex = index
        self.currentFeature = instances[index]
        lastSelectedFeatureID = instances[index].id
    }

    func setReviewScope(
        _ scope: AnnotationViewBaseReviewScope,
        currentClass: AccessibilityFeatureClass
    ) throws {
        guard !currentClass.kind.isUniquePerCapture else {
            reviewScope = .individual
            if currentFeature == nil, !instances.isEmpty {
                try setIndex(index: 0)
            }
            return
        }

        reviewScope = scope
        switch scope {
        case .all:
            try setIndex(index: nil)
        case .individual:
            let restoredIndex = lastSelectedFeatureID.flatMap { featureID in
                instances.firstIndex(where: { $0.id == featureID })
            } ?? instances.indices.first
            try setIndex(index: restoredIndex)
        }
    }

    func setGroupDecision(_ decision: AnnotationDecision) {
        objectWillChange.send()
        instances.forEach { $0.setGroupAnnotationDecision(decision) }
    }

    func setIndividualDecision(_ decision: AnnotationDecision) {
        guard let currentFeature else { return }
        objectWillChange.send()
        currentFeature.setIndividualAnnotationDecision(decision)
    }

    func clearIndividualDecision() {
        guard let currentFeature else { return }
        objectWillChange.send()
        currentFeature.setIndividualAnnotationDecision(nil)
    }
    
    func setCurrent(index: Int?, instances: [EditableAccessibilityFeature], currentClass: AccessibilityFeatureClass) throws {
        try setInstances(instances, currentClass: currentClass)
        try setIndex(index: index)
    }
    
    func setOptionOnFeature(option: AnnotationOption) {
        if let currentFeature = self.currentFeature {
            objectWillChange.send()
            currentFeature.setAnnotationOption(option)
        }
    }
}

class AnnotationViewStatusViewBaseModel: ObservableObject {
    @Published var isFailed: Bool = false
    @Published var errorMessage: String = ""
    @Published var shouldDismiss: Bool = true
    
    init(shouldDismiss: Bool = true) {
        self.shouldDismiss = shouldDismiss
    }
    
    func update(isFailed: Bool, errorMessage: String, shouldDismiss: Bool = true) {
        self.isFailed = isFailed
        self.errorMessage = errorMessage
        self.shouldDismiss = shouldDismiss
    }
    
    func update(isFailed: Bool, error: Error, shouldDismiss: Bool = true) {
        self.isFailed = isFailed
        let dismissKey = shouldDismiss ?
        AnnotationViewBaseConstants.Texts.managerStatusAlertMessageDismissScreenSuffixKey :
        AnnotationViewBaseConstants.Texts.managerStatusAlertMessageDismissAlertSuffixKey
        self.errorMessage = "\(error.localizedDescription) \(dismissKey)"
        self.shouldDismiss = shouldDismiss
    }
}

public struct AnnotationViewBase: View {
    let selectedClasses: [AccessibilityFeatureClass]
    let selectedAttributesByClass: [AccessibilityFeatureClass: Set<AccessibilityFeatureAttribute>]
    let captureLocation: CLLocationCoordinate2D
    let captureData: CaptureData
    let onCaptureComplete: ((CaptureData) -> Void)?
    /// MARK: Extra shared settings
    @EnvironmentObject public var sharedBaseSettings: SharedBaseSettings
    
    @EnvironmentObject var sharedAppData: SharedBaseData
    @EnvironmentObject var sharedBaseContext: SharedBaseContext
    @Environment(\.dismiss) var dismiss
    
    @StateObject var manager: AnnotationImageManager = AnnotationImageManager()
    
    @StateObject var segmentationAnnontationPipeline: SegmentationAnnotationPipeline = SegmentationAnnotationPipeline()
    @StateObject var attributeEstimationPipeline: AttributeEstimationPipeline = AttributeEstimationPipeline()
    
    @StateObject private var managerStatusViewModel = AnnotationViewStatusViewBaseModel()
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait // To bind one-way with manager's orientation
    
    @StateObject var featureClassSelectionViewModel = AnnotationFeatureClassSelectionViewBaseModel()
    @StateObject var featureSelectionViewModel = AnnotationFeatureSelectionViewBaseModel()
    @State private var isShowingAnnotationFeatureDetailView: Bool = false
    @State private var temporaryVisualizationFeatureID: UUID?
    @State private var temporaryVisualizationResults: AnnotationImageFeatureUpdateResults?
    
//    var selectFeatureInfoTipBase = SelectFeatureInfoTipBase()
    @State private var showSelectFeatureLearnMoreSheet = false
    
    public var body: some View {
        NavigationStack {
            Group {
//                HStack {
//                    Spacer()
//                    Text(AnnotationViewBaseConstants.Texts.annotationViewTitle)
//                        .font(.headline)
//                        .padding()
//                    Spacer()
//                }
//                .overlay(
//                    HStack {
//                        Spacer()
//                        Button(action: {
//                            dismiss()
//                        }) {
//                            Image(systemName: AnnotationViewBaseConstants.Images.closeIcon)
//                                .resizable()
//                                .frame(width: 20, height: 20)
//                        }
//                        .padding()
//                    }
//                )
                
                if let currentClass = featureClassSelectionViewModel.currentClass {
                    mainContent(currentClass: currentClass)
                } else {
                    loadingPageView()
                }
            }
            .navigationTitle(AnnotationViewBaseConstants.Texts.annotationViewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: AnnotationViewBaseConstants.Images.closeIcon)
                    }
                }
            }
        }
        .task {
            await handleOnAppear()
        }
        .onChange(of: featureClassSelectionViewModel.currentClass) { newClass in
            handleOnClassChange()
        }
        /// We are using index to track change in instance, instead of the instance itself, because we want to use the index for naming the instance in the picker.
        /// To use the instance directly would require AccessibilityFeature to conform to Hashable, which is possible, by just using id.
        /// But while rendering the picker, we would need to create a new Array of enumerated instances, which would be less efficient.
        .onChange(of: featureSelectionViewModel.currentIndex) { [oldIndex = featureSelectionViewModel.currentIndex] newIndex in
            handleOnInstanceChange(oldIndex: oldIndex, newIndex: newIndex)
        }
        .sheet(isPresented: $isShowingAnnotationFeatureDetailView) {
            if let currentFeature = featureSelectionViewModel.currentFeature,
               let currentFeatureIndex = featureSelectionViewModel.currentIndex
            {
                AnnotationFeatureDetailViewBase(
                    accessibilityFeature: currentFeature,
                    title: instanceDisplayName(
                        for: currentFeature.accessibilityFeatureClass,
                        index: currentFeatureIndex
                    )
                ) { feature in
                    EmptyView()
                }
                    .presentationDetents([.medium, .large])
            } else {
                Text(AnnotationViewBaseConstants.Texts.featureDetailNotAvailableText)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showSelectFeatureLearnMoreSheet) {
            SelectFeatureLearnMoreSheetView()
                .presentationDetents([.medium, .large])
        }
        .alert(AnnotationViewBaseConstants.Texts.managerStatusAlertTitleKey, isPresented: $managerStatusViewModel.isFailed, actions: {
            Button(AnnotationViewBaseConstants.Texts.managerStatusAlertDismissButtonKey) {
                let shouldDismiss = managerStatusViewModel.shouldDismiss
                managerStatusViewModel.update(isFailed: false, errorMessage: "")
                if shouldDismiss {
                    dismiss()
                }
            }
        }, message: {
            Text(managerStatusViewModel.errorMessage)
        })
    }
    
    private func loadingPageView() -> some View {
        VStack {
            Spacer()
            Text(AnnotationViewBaseConstants.Texts.loadingPageText)
            SpinnerView()
            Spacer()
        }
    }
    
    @ViewBuilder
    private func mainContent(currentClass: AccessibilityFeatureClass) -> some View {
        GeometryReader { geometry in
            let isLandscape = manager.interfaceOrientation.isLandscape
            let layout = isLandscape
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            layout {
                annotationImageView
                    .frame(
                        width: isLandscape ? geometry.size.width / 2 : geometry.size.width,
                        height: isLandscape ? geometry.size.height : geometry.size.height / 2
                    )

                annotationPane(currentClass: currentClass)
                    .frame(
                        width: isLandscape ? geometry.size.width / 2 : geometry.size.width,
                        height: isLandscape ? geometry.size.height : geometry.size.height / 2
                    )
            }
        }
    }

    private var annotationImageView: some View {
        HostedAnnotationImageViewController<EditableAccessibilityFeature>(annotationImageManager: manager)
            .clipped()
    }

    private func annotationPane(currentClass: AccessibilityFeatureClass) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                annotationControls(currentClass: currentClass)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }

            Divider()

            confirmAnnotationButton
                .frame(maxWidth: .infinity)
                .background(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: -2)
        }
    }

    @ViewBuilder
    private func annotationControls(currentClass: AccessibilityFeatureClass) -> some View {
        if featureSelectionViewModel.instances.isEmpty {
            emptyInstancesView(currentClass: currentClass)
        } else {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Text("\(AnnotationViewBaseConstants.Texts.currentClassPrefixText): \(currentClass.name)")
                        .font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .overlay(
                    HStack {
                        Spacer()
                        Button(action: {
                            showSelectFeatureLearnMoreSheet = true
                        }) {
                            Image(systemName: AnnotationViewBaseConstants.Images.infoIcon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        .padding(.trailing, 10)
                    }
                )

                Divider()

                if currentClass.kind == .sidewalk {
                    sidewalkReviewRuleView
                }

                if !currentClass.kind.isUniquePerCapture {
                    reviewScopePicker(currentClass: currentClass)
                }

                if currentClass.kind.isUniquePerCapture
                    || featureSelectionViewModel.reviewScope == .individual {
                    individualSelectionView(currentClass: currentClass)
                }

                if !currentClass.kind.isUniquePerCapture
                    && featureSelectionViewModel.reviewScope == .individual {
                    effectiveDecisionView()
                    Text("Override for this \(currentClass.name.capitalized)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                annotationOptionsView(currentClass: currentClass)
                decisionSummaryView(currentClass: currentClass)
            }
        }
    }

    private func emptyInstancesView(currentClass: AccessibilityFeatureClass) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No instances of \(currentClass.name.capitalized) were present.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var sidewalkReviewRuleView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            (
                Text("\(AnnotationViewBaseConstants.Texts.reviewRulePrefixText) ")
                    .fontWeight(.semibold)
                + Text(AnnotationViewBaseConstants.Texts.sidewalkReviewRuleText)
            )
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private var confirmAnnotationButton: some View {
        let isLastClass = isCurrentIndexLast()

        return Button(action: {
            confirmAnnotation()
        }) {
            HStack(spacing: 8) {
                Text(isLastClass
                     ? AnnotationViewBaseConstants.Texts.finishText
                     : AnnotationViewBaseConstants.Texts.nextText)
                Image(systemName: isLastClass ? "checkmark.seal.fill" : "arrow.right")
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.tint, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func reviewScopePicker(currentClass: AccessibilityFeatureClass) -> some View {
        Picker(
            AnnotationViewBaseConstants.Texts.selectObjectText,
            selection: Binding(
                get: { featureSelectionViewModel.reviewScope },
                set: { scope in
                    do {
                        try featureSelectionViewModel.setReviewScope(scope, currentClass: currentClass)
                    } catch {
                        managerStatusViewModel.update(
                            isFailed: true,
                            error: error,
                            shouldDismiss: false
                        )
                    }
                }
            )
        ) {
            Text("\(AnnotationViewBaseConstants.Texts.allText) (\(featureSelectionViewModel.instances.count))")
                .tag(AnnotationViewBaseReviewScope.all)
            Text(AnnotationViewBaseConstants.Texts.individualText)
                .tag(AnnotationViewBaseReviewScope.individual)
        }
        .pickerStyle(.segmented)
    }

    private func individualSelectionView(currentClass: AccessibilityFeatureClass) -> some View {
        HStack(spacing: 8) {
            if currentClass.kind.isUniquePerCapture {
                Text(instanceDisplayName(for: currentClass, index: 0))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker(
                    AnnotationViewBaseConstants.Texts.selectObjectText,
                    selection: $featureSelectionViewModel.currentIndex
                ) {
                    ForEach(featureSelectionViewModel.instances.indices, id: \.self) { featureIndex in
                        Text(instanceDisplayName(for: currentClass, index: featureIndex))
                            .tag(featureIndex as Int?)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                isShowingAnnotationFeatureDetailView = true
            } label: {
                Label(
                    AnnotationViewBaseConstants.Texts.detailsText,
                    systemImage: "doc.text"
                )
            }
            .buttonStyle(.bordered)
            .disabled(featureSelectionViewModel.currentFeature == nil)
        }
    }

    @ViewBuilder
    private func annotationOptionsView(currentClass: AccessibilityFeatureClass) -> some View {
        if currentClass.kind.isUniquePerCapture
            || featureSelectionViewModel.reviewScope == .individual {
            let selectedDecision = currentClass.kind.isUniquePerCapture
                ? featureSelectionViewModel.currentFeature?.effectiveAnnotationDecision
                : featureSelectionViewModel.currentFeature?.individualAnnotationDecision
            HStack(spacing: 8) {
                decisionButton(
                    title: AnnotationViewBaseConstants.Texts.keepText,
                    systemImage: AnnotationViewBaseConstants.Images.checkIcon,
                    decision: .keep,
                    selectedDecision: selectedDecision
                ) {
                    featureSelectionViewModel.setIndividualDecision(.keep)
                }
                decisionButton(
                    title: AnnotationViewBaseConstants.Texts.discardText,
                    systemImage: "trash",
                    decision: .discard,
                    selectedDecision: selectedDecision
                ) {
                    featureSelectionViewModel.setIndividualDecision(.discard)
                }
            }
        } else {
            HStack(spacing: 8) {
                decisionButton(
                    title: "\(AnnotationViewBaseConstants.Texts.keepText) All",
                    systemImage: AnnotationViewBaseConstants.Images.checkIcon,
                    decision: .keep,
                    selectedDecision: featureSelectionViewModel.groupDecision
                ) {
                    featureSelectionViewModel.setGroupDecision(.keep)
                }
                decisionButton(
                    title: "\(AnnotationViewBaseConstants.Texts.discardText) All",
                    systemImage: "trash",
                    decision: .discard,
                    selectedDecision: featureSelectionViewModel.groupDecision
                ) {
                    featureSelectionViewModel.setGroupDecision(.discard)
                }
            }
        }
    }

    private func decisionButton(
        title: String,
        systemImage: String,
        decision: AnnotationDecision,
        selectedDecision: AnnotationDecision?,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = selectedDecision == decision
        let decisionColor: Color = decision == .keep ? .green : .red

        return Button(action: action) {
            Label(title, systemImage: systemImage)
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
    }

    @ViewBuilder
    private func effectiveDecisionView() -> some View {
        if let currentFeature = featureSelectionViewModel.currentFeature {
            let decision = currentFeature.effectiveAnnotationDecision
            let decisionColor: Color = decision == .keep ? .green : .red
            let sourceText = currentFeature.individualAnnotationDecision == nil
                ? AnnotationViewBaseConstants.Texts.fromGroupText
                : AnnotationViewBaseConstants.Texts.individualChoiceText

            HStack(spacing: 12) {
                Label {
                    HStack(spacing: 4) {
                        Text(decision == .keep
                             ? AnnotationViewBaseConstants.Texts.keepText
                             : AnnotationViewBaseConstants.Texts.discardText)
                            .fontWeight(.semibold)
                        Text("(\(sourceText))")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: decision == .keep
                          ? AnnotationViewBaseConstants.Images.checkIcon
                          : "trash")
                }
                .foregroundStyle(decisionColor)

                Spacer(minLength: 0)

                Button(AnnotationViewBaseConstants.Texts.useGroupDecisionText) {
                    featureSelectionViewModel.clearIndividualDecision()
                }
                .buttonStyle(.bordered)
                .disabled(currentFeature.individualAnnotationDecision == nil)
            }
            .font(.subheadline)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(decisionColor.opacity(0.1))
            )
        }
    }

    private func decisionSummaryView(currentClass: AccessibilityFeatureClass) -> some View {
        let summary = featureSelectionViewModel.decisionSummary
        return HStack(spacing: 8) {
            Text("\(summary.keptCount) kept")
                .foregroundStyle(.green)
            Text("·")
            Text("\(summary.discardedCount) discarded")
                .foregroundStyle(.red)
            if !currentClass.kind.isUniquePerCapture {
                Text("·")
                Text("\(summary.exceptionCount) exceptions")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func instanceDisplayName(
        for featureClass: AccessibilityFeatureClass,
        index: Int
    ) -> String {
        "\(featureClass.name.capitalized) #\(index + 1)"
    }
    
    private func isCurrentIndexValid() -> Bool {
        guard let currentCaptureDataRecord = sharedAppData.currentCaptureDataRecord,
              let currentClassIndex = featureClassSelectionViewModel.currentIndex else {
            return false
        }
        let segmentedClasses = currentCaptureDataRecord.imageData.captureImageDataResults.segmentedClasses
        return (currentClassIndex >= 0 && currentClassIndex < segmentedClasses.count)
    }
    
    private func isCurrentIndexLast() -> Bool {
        guard let currentCaptureDataRecord = sharedAppData.currentCaptureDataRecord,
              let currentClassIndex = featureClassSelectionViewModel.currentIndex else {
            return false
        }
        let segmentedClasses = currentCaptureDataRecord.imageData.captureImageDataResults.segmentedClasses
        return currentClassIndex == segmentedClasses.count - 1
    }
    
    private func handleOnAppear() async {
        do {
            guard let currentCaptureDataRecord = sharedAppData.currentCaptureDataRecord else {
                throw AnnotationViewBaseError.invalidCaptureDataRecord
            }
            var captureMeshData: (any CaptureMeshDataProtocol)? = nil
            if sharedBaseSettings.isEnhancedAnalysisEnabled {
                guard let captureMeshDataResults = currentCaptureDataRecord.meshData?.captureMeshDataResults else {
                    throw AnnotationViewBaseError.invalidCaptureDataRecord
                }
                captureMeshData = CaptureImageAndMeshData(
                    captureImageData: CaptureImageData(currentCaptureDataRecord.imageData),
                    captureMeshDataResults: captureMeshDataResults
                )
            }
            let segmentedClasses = currentCaptureDataRecord.imageData.captureImageDataResults.segmentedClasses
            try segmentationAnnontationPipeline.configure()
            try attributeEstimationPipeline.configure(
                captureImageData: currentCaptureDataRecord.imageData,
                captureMeshData: captureMeshData
            )
            try manager.configure(
                selectedClasses: selectedClasses, segmentationAnnotationPipeline: segmentationAnnontationPipeline,
                captureImageData: currentCaptureDataRecord.imageData,
                captureMeshData: captureMeshData,
                isEnhancedAnalysisEnabled: sharedBaseSettings.isEnhancedAnalysisEnabled
            )
            let captureDataHistory = Array(await sharedAppData.captureDataQueue.snapshot())
            manager.setupAlignedSegmentationLabelImages(captureDataHistory: captureDataHistory)
            try featureClassSelectionViewModel.setCurrent(index: 0, classes: segmentedClasses)
        } catch {
            managerStatusViewModel.update(isFailed: true, error: error)
        }
    }
    
    private func handleOnClassChange() {
        do {
            guard let currentClass = featureClassSelectionViewModel.currentClass else {
                throw AnnotationViewBaseError.invalidCaptureDataRecord
            }
            temporaryVisualizationFeatureID = nil
            temporaryVisualizationResults = nil
            let accessibilityFeatures = try manager.updateFeatureClass(accessibilityFeatureClass: currentClass)
            var lastEstimationError: Error? = nil
            for (index, accessibilityFeature) in accessibilityFeatures.enumerated() {
                do {
//                    try attributeEstimationPipeline.setPrerequisites(accessibilityFeature: accessibilityFeature)
                    try attributeEstimationPipeline.processLocationRequest(
                        deviceLocation: captureLocation,
                        accessibilityFeature: accessibilityFeature
                    )
                    try attributeEstimationPipeline.processAttributeRequest(
                        accessibilityFeature: accessibilityFeature,
                        attributes: selectedAttributesByClass[currentClass] ?? []
                    )
                    if index == accessibilityFeatures.index(before: accessibilityFeatures.endIndex),
                       currentClass.kind.attributes.contains(where: {
                           $0 == .width || $0 == .runningSlope || $0 == .crossSlope
                               || $0 == .surfaceIntegrity
                       }) {
                        temporaryVisualizationFeatureID = accessibilityFeature.id
                        temporaryVisualizationResults = try makeVisualizationResults(
                            for: accessibilityFeature
                        )
                    }
                    attributeEstimationPipeline.clearPrerequisites()
                } catch {
                    lastEstimationError = error
                }
            }
            featureClassSelectionViewModel.setOption(option: .classOption(.default))
            try featureSelectionViewModel.setInstances(accessibilityFeatures, currentClass: currentClass)
            if let lastEstimationError {
                throw AnnotationViewBaseError.attributeEstimationFailed(lastEstimationError)
            }
        } catch AnnotationViewBaseError.attributeEstimationFailed(let error) {
            managerStatusViewModel.update(
                isFailed: true, error: AnnotationViewBaseError.attributeEstimationFailed(error), shouldDismiss: false
            )
        } catch {
            managerStatusViewModel.update(isFailed: true, error: error, shouldDismiss: false)
        }
    }
    
    private func handleOnInstanceChange(oldIndex: Int?, newIndex: Int?) {
        do {
            try featureSelectionViewModel.setIndex(index: featureSelectionViewModel.currentIndex)
        } catch {
            managerStatusViewModel.update(isFailed: true, error: error)
        }
        do {
            guard let currentClass = featureClassSelectionViewModel.currentClass else {
                throw AnnotationViewBaseError.invalidCaptureDataRecord
            }
            var selection: AnnotationImageSelection<EditableAccessibilityFeature>?
            var updateFeatureResults: AnnotationImageFeatureUpdateResults? = nil
            if let currentFeature = featureSelectionViewModel.currentFeature,
               let currentIndex = featureSelectionViewModel.currentIndex {
                selection = AnnotationImageSelection(
                    feature: currentFeature,
                    index: currentIndex
                )
                if currentClass.kind.attributes.contains(where: {
                    $0 == .width || $0 == .runningSlope || $0 == .crossSlope || $0 == .surfaceIntegrity
                }) {
                    if temporaryVisualizationFeatureID == currentFeature.id,
                       let temporaryVisualizationResults {
                        updateFeatureResults = temporaryVisualizationResults
                    } else {
                        attributeEstimationPipeline.clearPrerequisites()
                        updateFeatureResults = try makeVisualizationResults(for: currentFeature)
                    }
                }
            }
            try manager.updateFeature(
                accessibilityFeatureClass: currentClass,
                selection: selection,
                updateFeatureResults: updateFeatureResults
            )
        } catch {
            managerStatusViewModel.update(isFailed: true, error: error, shouldDismiss: false)
        }
    }

    private func makeVisualizationResults(
        for accessibilityFeature: EditableAccessibilityFeature
    ) throws -> AnnotationImageFeatureUpdateResults {
        let worldPoints = try attributeEstimationPipeline.getCachedWorldPoints(
            accessibilityFeature: accessibilityFeature
        )
        let plane = try attributeEstimationPipeline.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature,
            worldPoints: worldPoints
        )
        let projectedPlane = try attributeEstimationPipeline.getCachedProjectedPlane(
            accessibilityFeature: accessibilityFeature,
            plane: plane
        )
        let damageDetectionResults = try attributeEstimationPipeline.getCachedDamageDetectionResults(
            accessibilityFeature: accessibilityFeature
        )
        let surfaceIntegrityWindowAnalysis = try? attributeEstimationPipeline
            .getCachedSurfaceIntegrityWindowAnalysis(
                accessibilityFeature: accessibilityFeature
            )
        return AnnotationImageFeatureUpdateResults(
            plane: plane,
            projectedPlane: projectedPlane,
            damageDetectionResults: damageDetectionResults,
            surfaceIntegrityWindowAnalysis: surfaceIntegrityWindowAnalysis
        )
    }
    
    private func confirmAnnotation() {
        Task {
            do {
                try moveToNextClass()
            } catch AnnotationViewBaseError.classIndexOutofBounds {
                managerStatusViewModel.update(isFailed: true, error: AnnotationViewBaseError.classIndexOutofBounds)
            } catch {
                managerStatusViewModel.update(isFailed: true, error: error, shouldDismiss: false)
            }
        }
    }
    
    private func moveToNextClass() throws {
        if isCurrentIndexLast() {
            onCaptureComplete?(captureData)
            dismiss()
            return
        }
        /// Move to next class
        guard let currentCaptureDataRecord = sharedAppData.currentCaptureDataRecord,
              let currentClassIndex = featureClassSelectionViewModel.currentIndex else {
            throw AnnotationViewBaseError.invalidCaptureDataRecord
        }
        let segmentedClasses = currentCaptureDataRecord.imageData.captureImageDataResults.segmentedClasses
        try featureClassSelectionViewModel.setCurrent(index: currentClassIndex + 1, classes: segmentedClasses)
    }
}

struct SelectFeatureLearnMoreSheetView: View {
    @Environment(\.dismiss)
    var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            //            Image(systemName: "number")
            //                .resizable()
            //                .scaledToFit()
            //                .frame(width: 160)
            //                .foregroundStyle(.accentColor)
            Text(AnnotationViewBaseConstants.Texts.selectFeatureInfoLearnMoreSheetTitle)
                .font(.headline)
            Text(AnnotationViewBaseConstants.Texts.selectFeatureInfoLearnMoreSheetMessage)
                .foregroundStyle(.secondary)
            Button("Dismiss") {
                dismiss()
            }
        }
        .padding(.horizontal, 40)
    }
}
