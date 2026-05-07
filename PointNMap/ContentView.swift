//
//  ContentView.swift
//  PointNMap
//
//  Created by Himanshu on 5/6/26.
//

import SwiftUI
import PointNMapShared

enum ContentViewConstants {
    enum Texts {
        static let setupViewTitle = "Setup"
        static let selectedWorkspaceTitle = "Selected Workspace"
        static let uploadChangesetTitle = "Upload Changeset"
        static let selectClassesText = "Select Feature Types to Map"
        
        /// Alerts
        static let changesetOpeningErrorTitle = "Changeset failed to open. Please retry."
        static let changesetOpeningRetryText = "Retry"
        static let changesetOpeningRetryMessageText = "Failed to open changeset."
        static let changesetOpeningBackText = "Back"
        static let workspaceIdMissingMessageText = "Workspace ID is missing."
        static let changesetClosingErrorTitle = "Changeset failed to close. Please retry."
        static let changesetClosingRetryText = "Retry"
        static let changesetClosingRetryMessageText = "Failed to close changeset."
        static let modelInitializationErrorTitle = "Machine Learning Model initialization failed. Please retry."
        static let modelInitializationRetryText = "Retry"
        static let modelInitializationRetryMessageText = "Failed to initialize the machine learning model."
        static let sharedAppContextInitializationErrorTitle = "App Context configuration failed. Please retry."
        static let sharedAppContextInitializationRetryText = "Retry"
        static let sharedAppContextInitializationRetryMessageText = "Failed to configure the app context."
        
        static let confirmationDialogTitle = "Are you sure you want to log out?"
        static let confirmationDialogConfirmText = "Log out"
        static let confirmationDialogCancelText = "Cancel"
        
        static let nextButton = "Next"
        
        /// ChangesetInfoTip
        static let changesetInfoTipTitle = "Upload Changeset"
        static let changesetInfoTipMessage = "Upload your collected data as a changeset to the workspace."
        static let changesetInfoTipLearnMoreButtonTitle = "Learn More"
        
        /// ChangesetInfoLearnMoreSheetView
        static let changesetInfoLearnMoreSheetTitle = "About Changesets"
        static let changesetInfoLearnMoreSheetMessage = """
        A changeset is a collection of changes made to the workspace. It allows you to group related modifications together for easier management and tracking.
        
        Click the Upload Changeset button to upload your collected data as a changeset to the workspace.
        """
        
        /// SelectClassesInfoTip
        static let selectClassesInfoTipTitle = "Select Feature Types"
        static let selectClassesInfoTipMessage = "Please select the type of environment features that you want the application to map during the mapping session."
        static let selectClassesInfoTipLearnMoreButtonTitle = "Learn More"
        
        /// SelectClassesInfoLearnMoreSheetView
        static let selectClassesInfoLearnMoreSheetTitle = "About Feature Types"
        static let selectClassesInfoLearnMoreSheetMessage = """
        Each feature type represents a specific type of feature in the environment, such as sidewalks, buildings, traffic signs, etc.
        
        Selecting specific feature types helps the application focus on mapping the objects that are most relevant to your needs. 
        
        Please select the feature types you want to identify during the mapping session from the list provided.
        """
    }
    
    enum Images {
        static let profileIcon = "person.crop.circle"
        static let logoutIcon = "rectangle.portrait.and.arrow.right"
        static let uploadIcon = "arrow.up"
        static let classSelectionColorHintIcon = "circle.fill"
        static let classSelectionColorHintBorderIcon = "circle"
        
        /// InfoTip
        static let infoIcon = "info.circle"
    }
    
    enum Colors {
        static let selectedClass = Color(red: 187/255, green: 134/255, blue: 252/255)
        static let unselectedClass = Color.primary
    }
    
    enum Constraints {
        static let profileIconSize: CGFloat = 20
    }
    
    enum Identifiers {
        static let changesetInfoTipLearnMoreActionId: String = "changeset-learn-more"
        static let selectClassesInfoTipLearnMoreActionId: String = "select-classes-learn-more"
    }
}

struct ContentView: View {
    @State private var selectedClasses: [AccessibilityFeatureClass] = []
    
    var body: some View {
        return NavigationStack {
            VStack {
                List {
                    ForEach(selectedClasses, id: \.self) { accessibilityFeatureClass in
                        Button(action: {
                            
                        }) {
                            HStack {
                                Text(accessibilityFeatureClass.name)
                                    .foregroundStyle(ContentViewConstants.Colors.selectedClass)
                                Spacer()
                                Image(systemName: ContentViewConstants.Images.classSelectionColorHintIcon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(Color(UIColor(ciColor: accessibilityFeatureClass.color)))
                                    .overlay(
                                        Image(systemName: ContentViewConstants.Images.classSelectionColorHintBorderIcon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .foregroundStyle(ContentViewConstants.Colors.selectedClass)
                                    )
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarTitle(ContentViewConstants.Texts.setupViewTitle, displayMode: .inline)
        .navigationBarItems(
            trailing:
                NavigationLink(destination: mappingDestination) {
                    Text("Next")
                        .foregroundStyle(Color.primary)
                        .font(.headline)
                }
        )
        .onAppear {
            // For demonstration purposes, we select only sidewalk class by default
            guard let sidewalkClass = PointNMapConstants.SelectedAccessibilityFeatureConfig.classes.first(where: { $0.kind == .sidewalk }) else {
                return
            }
            self.selectedClasses = [sidewalkClass]
        }
    }
    
    @ViewBuilder
    private var mappingDestination: some View {
        ARCameraViewBase(selectedClasses: self.selectedClasses.sorted())
    }
}

//#Preview {
//    ContentView()
//}
