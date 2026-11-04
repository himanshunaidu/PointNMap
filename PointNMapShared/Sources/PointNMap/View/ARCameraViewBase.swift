//
//  ARCameraViewBase.swift
//  IOSAccessAssessment
//
//  Created by Kohei Matsushima on 2024/03/29.
//

import SwiftUI
import Combine
import AVFoundation
import Vision
import Metal
import CoreImage
import MetalKit
import CoreLocation

enum ARCameraViewBaseConstants {
    enum Texts {
        static let contentViewTitle = "Capture"
        
        static let cameraInProgressText = "Camera settings in progress"
        
        /// Camera Hint Texts
        static let cameraHintPlaceholderText = "..."
        static let cameraHintNoMeshText = "No Mesh Captured"
        static let cameraHintNoSegmentationText = "No Features Detected"
        static let cameraHintMeshNotProcessedText = "Features Not Processed"
        static let cameraHintLocationErrorText = "Location Error"
        static let cameraHintUnknownErrorText = "Unknown Error"
        static let cameraHintMappingDataNotReadyText = "Mapping Data Not Ready"
        
        static let permissionOpenSettingsButtonKey = "Open Settings"
        static let permissionNotNowButtonKey = "Not Now"
        
        /// Location Manager Alerts
        static let locationPermissionAlertTitleKey = "Location Access is Off"
        static let locationPermissionAlertMessageKey = """
        Open Settings and allow location access for this app. Keep Precise Location on. 
        Cannot proceed without precise location access.
        """
        static let preciseLocationPermissionAlertTitleKey = "Precise Location is Off"
        static let preciseLocationPermissionAlertMessageKey = """
        Open Settings for this app, tap Location, then turn on Precise Location. 
        Cannot proceed without precise location access.
        """
        
        /// Camera Permission Alert
        static let cameraPermissionAlertTitleKey = "Camera Access is Off"
        static let cameraPermissionAlertMessageKey = """
        Open Settings and allow camera access for this app.
        Cannot proceed without camera access.
        """
        
        /// Manager Status Alert
        static let managerStatusAlertTitleKey = "Error"
        static let managerStatusAlertDismissButtonKey = "OK"
        
        /// Mapping Data Status Alert
        static let mappingDataStatusAlertTitleKey = "Error"
        static let mappingDataStatusAlertRetryButtonKey = "Retry"
        static let mappingDataStatusAlertDismissButtonKey = "OK"
        
        /// Invalid Content View
        static let invalidContentViewTitle = "Invalid Capture"
        static let invalidContentViewMessage = "The captured data is invalid. Please try again."
        
    }
    
    enum Images {
        static let cameraIcon = "camera.circle.fill"
        static let inProgressIcon = "hourglass"
        
        /// InfoTio
        static let infoIcon = "info.circle"
    }
    
    enum Colors {
        static let selectedClass = Color(red: 187/255, green: 134/255, blue: 252/255)
        static let unselectedClass = Color.primary
    }
    
    enum Constraints {
        static let logoutIconSize: CGFloat = 20
        static let cameraIconSize: CGFloat = 60
        static let inProgressIconSize: CGFloat = 40
    }
}

enum ARCameraViewBaseError: Error, LocalizedError {
    case captureNoSegmentationAccessibilityFeatures
    case workspaceConfigurationFailed
    case authenticationError
    case mappingDataNotReady
    
    var errorDescription: String? {
        switch self {
        case .captureNoSegmentationAccessibilityFeatures:
            return "No accessibility features were captured. Please try again."
        case .workspaceConfigurationFailed:
            return "Workspace configuration failed. Please check your workspace settings."
        case .authenticationError:
            return "Authentication error. Please log in again."
        case .mappingDataNotReady:
            return "Mapping data is not ready yet. Please wait a moment and try again."
        }
    }
}

class ARCameraBaseManagerStatusViewModel: ObservableObject {
    @Published var isFailed: Bool = false
    @Published var errorMessage: String = ""
    
    func update(isFailed: Bool, errorMessage: String) {        
        self.isFailed = isFailed
        self.errorMessage = errorMessage
    }
}

public struct ARCameraViewBase: View {
    public let selectedClasses: [AccessibilityFeatureClass]
    public let selectedAttributesByClass: [AccessibilityFeatureClass: Set<AccessibilityFeatureAttribute>]
    /// Called after the user finishes annotating the captured data.
    private let onCaptureComplete: ((CaptureData) -> Void)?
    /// MARK: Extra shared settings
    @EnvironmentObject public var sharedBaseSettings: SharedBaseSettings
    
    @EnvironmentObject public var sharedAppData: SharedBaseData
    @EnvironmentObject public var sharedAppContext: SharedBaseContext
    @EnvironmentObject public var segmentationPipeline: SegmentationARPipeline
    @Environment(\.dismiss) public var dismiss

    @StateObject private var manager: ARCameraManager = ARCameraManager()
    @StateObject private var managerConfigureStatusViewModel = ARCameraBaseManagerStatusViewModel()
    @State private var captureFailureExplanation: String?
    @State private var isCaptureInProgress = false
    
    @StateObject private var locationManager: LocationManager = LocationManager()
    
    @State private var showARCameraLearnMoreSheet = false
    
    @State private var showAnnotationView = false
    @State private var completedCaptureData: CaptureData?
    
    public init(
        selectedClasses: [AccessibilityFeatureClass],
        selectedAttributesByClass: [AccessibilityFeatureClass: Set<AccessibilityFeatureAttribute>],
        onCaptureComplete: ((CaptureData) -> Void)?
    ) {
        self.selectedClasses = selectedClasses
        self.selectedAttributesByClass = selectedAttributesByClass
        self.onCaptureComplete = onCaptureComplete
    }
    
    public var body: some View {
        Group {
            if manager.isConfigured {
                orientationStack {
                    HostedARCameraViewContainer(arSessionCameraProcessingDelegate: manager)
                        .layoutPriority(1)

                    CaptureControlPanel(
                        state: capturePresentationState,
                        captureAction: cameraCapture,
                        helpAction: { showARCameraLearnMoreSheet = true }
                    )
                }
            } else {
                VStack {
                    Spacer()

                    CaptureControlPanel(
                        state: .preparing,
                        captureAction: cameraCapture,
                        helpAction: { showARCameraLearnMoreSheet = true }
                    )
                }
            }
        }
        .navigationBarTitle(ARCameraViewBaseConstants.Texts.contentViewTitle, displayMode: .inline)
        .onAppear {
            locationManager.startLocationUpdates()
            showAnnotationView = false
            do {
                try segmentationPipeline.setSelectedClasses(selectedClasses)
                try manager.configure(
                    selectedClasses: selectedClasses, segmentationPipeline: segmentationPipeline,
                    metalContext: sharedAppContext.metalContext,
                    isEnhancedAnalysisEnabled: sharedBaseSettings.isEnhancedAnalysisEnabled,
                    cameraOutputImageCallback: cameraOutputImageCallback
                )
            } catch {
                managerConfigureStatusViewModel.update(isFailed: true, errorMessage: error.localizedDescription)
            }
        }
        .onDisappear {
            Task {
                do {
                    try await manager.pause()
                    locationManager.stopLocationUpdates()
                } catch {
                    print("Error pausing ARCameraManager: \(error)")
                }
            }
        }
        .alert(ARCameraViewBaseConstants.Texts.locationPermissionAlertTitleKey, isPresented: $locationManager.shouldShowLocationPermissionAlert, actions: {
            Button(ARCameraViewBaseConstants.Texts.permissionOpenSettingsButtonKey) {
                openAppSettings()
                dismiss()
            }
            Button(ARCameraViewBaseConstants.Texts.permissionNotNowButtonKey, role: .cancel) {
                dismiss()
            }
        }, message: {
            Text(ARCameraViewBaseConstants.Texts.locationPermissionAlertMessageKey)
        })
        .alert(ARCameraViewBaseConstants.Texts.preciseLocationPermissionAlertTitleKey, isPresented: $locationManager.shouldShowPreciseLocationAlert, actions: {
            Button(ARCameraViewBaseConstants.Texts.permissionOpenSettingsButtonKey) {
                openAppSettings()
                dismiss()
            }
            Button(ARCameraViewBaseConstants.Texts.permissionNotNowButtonKey, role: .cancel) {
                dismiss()
            }
        }, message: {
            Text(ARCameraViewBaseConstants.Texts.preciseLocationPermissionAlertMessageKey)
        })
        .alert(ARCameraViewBaseConstants.Texts.cameraPermissionAlertTitleKey, isPresented: $manager.shouldShowCameraPermissionAlert, actions: {
            Button(ARCameraViewBaseConstants.Texts.permissionOpenSettingsButtonKey) {
                openAppSettings()
                dismiss()
            }
            Button(ARCameraViewBaseConstants.Texts.permissionNotNowButtonKey, role: .cancel) {
                dismiss()
            }
        }, message: {
            Text(ARCameraViewBaseConstants.Texts.cameraPermissionAlertMessageKey)
        })
        .alert(ARCameraViewBaseConstants.Texts.managerStatusAlertTitleKey, isPresented: $managerConfigureStatusViewModel.isFailed, actions: {
            Button(ARCameraViewBaseConstants.Texts.managerStatusAlertDismissButtonKey) {
                managerConfigureStatusViewModel.update(isFailed: false, errorMessage: "")
                dismiss()
            }
        }, message: {
            Text(managerConfigureStatusViewModel.errorMessage)
        })
        .fullScreenCover(isPresented: $showAnnotationView) {
            if let captureLocation = locationManager.currentLocation?.coordinate,
               let completedCaptureData {
                AnnotationViewBase(
                    selectedClasses: selectedClasses, selectedAttributesByClass: selectedAttributesByClass,
                    captureLocation: captureLocation, captureData: completedCaptureData,
                    onCaptureComplete: onCaptureComplete
                )
            } else {
                InvalidContentView(
                    title: ARCameraViewBaseConstants.Texts.invalidContentViewTitle,
                    message: ARCameraViewBaseConstants.Texts.invalidContentViewMessage
                )
            }
        }
        .onChange(of: showAnnotationView) { newValue in
            // If the AnnotationView is dismissed, clear capture history and reconfigure the manager for a new session
            Task {
                if !newValue {
                    do {
                        locationManager.startLocationUpdates()
                        await sharedAppData.refreshQueue()
                        try manager.resume()
                    } catch {
                        managerConfigureStatusViewModel.update(isFailed: true, errorMessage: error.localizedDescription)
                    }
                }
            }
        }
        .onChange(of: manager.interfaceOrientation) { newOrientation in
            locationManager.updateOrientation(newOrientation)
        }
        .onChange(of: locationManager.currentLocation) { [oldLocation = locationManager.currentLocation] newLocation in
            handleLocationUpdate(oldLocation: oldLocation, newLocation: newLocation)
        }
        .sheet(isPresented: $showARCameraLearnMoreSheet) {
            CaptureHelpView()
                .presentationDetents([.large])
        }
    }

    private var capturePresentationState: CapturePresentationState {
        if isCaptureInProgress {
            return .processing
        }
        if let captureFailureExplanation {
            return .captureFailed(explanation: captureFailureExplanation)
        }
        return manager.isCaptureReady ? .ready : .preparing
    }
    
    @ViewBuilder
    private func orientationStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        manager.interfaceOrientation.isLandscape ?
        AnyLayout(HStackLayout())(content) :
        AnyLayout(VStackLayout())(content)
    }
    
    private func cameraOutputImageCallback(_ captureImageData: (any CaptureImageDataProtocol)) {
        Task {
            await sharedAppData.appendCaptureDataToQueue(captureImageData)
        }
    }
    
    private func cameraCapture() {
        guard !isCaptureInProgress, !showAnnotationView else { return }

        isCaptureInProgress = true
        captureFailureExplanation = nil

        Task {
            defer { isCaptureInProgress = false }

            do {
                let captureData: CaptureData = try await manager.performFinalSessionUpdateIfPossible()
                switch captureData {
                case .imageData(let data):
                    if (data.captureImageDataResults.segmentedClasses.isEmpty)
                    {
                        throw ARCameraViewBaseError.captureNoSegmentationAccessibilityFeatures
                    }
                case .imageAndMeshData(let data):
                    if (data.captureImageDataResults.segmentedClasses.isEmpty)
                    || (data.captureMeshDataResults.segmentedMesh.totalVertexCount == 0)
                    {
                        throw ARCameraViewBaseError.captureNoSegmentationAccessibilityFeatures
                    }
                }
                try await manager.pause()
                locationManager.stopLocationUpdates()
                /// Get location. Done after pausing the manager to avoid delays, despite being less accurate.
                sharedAppData.saveCaptureData(captureData)
                addCaptureDataToCurrentDataset(
                    captureImageData: captureData.imageData, captureMeshData: captureData.meshData,
                    location: locationManager.currentLocation?.coordinate, heading: locationManager.currentHeading?.trueHeading
                )
//                if let onCaptureComplete = onCaptureComplete {
//                    onCaptureComplete(captureData)
//                    dismiss()
//                } else {
//                    showAnnotationView = true
//                }
                completedCaptureData = captureData
                showAnnotationView = true
            } catch ARCameraManagerError.finalSessionMeshUnavailable {
                setCaptureFailure(ARCameraViewBaseConstants.Texts.cameraHintNoMeshText)
            } catch ARCameraManagerError.finalSessionNoSegmentationClass,
                ARCameraViewBaseError.captureNoSegmentationAccessibilityFeatures {
                setCaptureFailure(ARCameraViewBaseConstants.Texts.cameraHintNoSegmentationText)
            } catch ARCameraManagerError.finalSessionNoSegmentationMesh {
                setCaptureFailure(ARCameraViewBaseConstants.Texts.cameraHintMeshNotProcessedText)
            } catch ARCameraViewBaseError.mappingDataNotReady {
                setCaptureFailure(ARCameraViewBaseConstants.Texts.cameraHintMappingDataNotReadyText)
            } catch _ as LocationManagerError {
                setCaptureFailure(ARCameraViewBaseConstants.Texts.cameraHintLocationErrorText)
            } catch {
                setCaptureFailure(ARCameraViewBaseConstants.Texts.cameraHintUnknownErrorText)
            }
        }
    }
    
    private func addCaptureDataToCurrentDataset(
        captureImageData: any CaptureImageDataProtocol,
        captureMeshData: (any CaptureMeshDataProtocol)? = nil,
        location: CLLocationCoordinate2D?,
        heading: CLLocationDirection?
    ) {
    }
    
    private func handleLocationUpdate(oldLocation: CLLocation?, newLocation: CLLocation?) {
        var shouldUpdateMap = oldLocation == nil && newLocation != nil
        if let oldLocation, let newLocation {
            let distance = oldLocation.distance(from: newLocation)
            shouldUpdateMap = distance > PointNMapConstants.WorkspaceConstants.fetchUpdateRadiusThresholdInMeters
        }
        if !shouldUpdateMap {
            return
        }
    }
    
    private func setCaptureFailure(_ text: String) {
        captureFailureExplanation = text
    }
    
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }

        UIApplication.shared.open(url)
    }
}

