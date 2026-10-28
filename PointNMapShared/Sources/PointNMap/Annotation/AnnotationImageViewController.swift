//
//  AnnotationCameraViewController.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/10/25.
//

import SwiftUI
import Combine

@MainActor
public protocol AnnotationImageProcessingOutputConsumer: AnyObject {
    func annotationOutputImage(
        _ delegate: AnnotationImageProcessingDelegate, cameraImage: CIImage?,
        segmentationOverlayImage: CIImage?, featureGeometryOverlayImage: CIImage?,
        surfaceAnalysisOverlayImage: CIImage?
    )
    func annotationSelectionSpotlightImage(
        _ delegate: AnnotationImageProcessingDelegate,
        selectionSpotlightOverlayImage: CIImage?
    )
}

public extension AnnotationImageProcessingOutputConsumer {
    func annotationSelectionSpotlightImage(
        _ delegate: AnnotationImageProcessingDelegate,
        selectionSpotlightOverlayImage: CIImage?
    ) {}
}

public protocol AnnotationImageProcessingDelegate: AnyObject {
    @MainActor
    var outputConsumer: AnnotationImageProcessingOutputConsumer? { get set }
    @MainActor
    func setOrientation(_ orientation: UIInterfaceOrientation)
}

public class AnnotationImageViewController<Feature: EditableAccessibilityFeature>: UIViewController, AnnotationImageProcessingOutputConsumer {
    public var annotationImageManager: AnnotationImageManager<Feature>
    
    private let subView = UIView()
    
    private let cameraImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.0)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let segmentationOverlayImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.0)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let featureGeometryOverlayImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.0)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let surfaceAnalysisOverlayImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.0)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let selectionSpotlightOverlayImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = UIColor(white: 0, alpha: 0.0)
        iv.isUserInteractionEnabled = false
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    public init(annotationImageManager: AnnotationImageManager<Feature>) {
        self.annotationImageManager = annotationImageManager
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(subView)
        subView.clipsToBounds = true
        subView.translatesAutoresizingMaskIntoConstraints = false
        let subViewBoundsConstraints: [NSLayoutConstraint] = [
            subView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subView.topAnchor.constraint(equalTo: view.topAnchor),
            subView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(subViewBoundsConstraints)
        
        subView.addSubview(cameraImageView)
        constraintChildViewToParent(childView: cameraImageView, parentView: subView)
        subView.addSubview(segmentationOverlayImageView)
        constraintChildViewToParent(childView: segmentationOverlayImageView, parentView: subView)
        subView.addSubview(featureGeometryOverlayImageView)
        constraintChildViewToParent(childView: featureGeometryOverlayImageView, parentView: subView)
        subView.addSubview(surfaceAnalysisOverlayImageView)
        constraintChildViewToParent(childView: surfaceAnalysisOverlayImageView, parentView: subView)
        subView.addSubview(selectionSpotlightOverlayImageView)
        constraintChildViewToParent(childView: selectionSpotlightOverlayImageView, parentView: subView)
        
        annotationImageManager.outputConsumer = self
        annotationImageManager.setOrientation(getOrientation())
    }
    
    private func constraintChildViewToParent(childView: UIView, parentView: UIView) {
        NSLayoutConstraint.deactivate(childView.constraints)
        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: parentView.topAnchor),
            childView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            childView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
        ])
    }
    
    public func getOrientation() -> UIInterfaceOrientation {
        // TODO: While we are requested to replace usage with effectiveGeometry.interfaceOrientation,
        //  it seems to cause issues with getting the correct orientation.
        //  Need to investigate further.
        if let io = view.window?.windowScene?.interfaceOrientation {
            return io
        }
        // Fallback for early lifecycle / no window
        if view.bounds.height >= view.bounds.width {
            return .portrait
        }
        return .landscapeLeft
    }
    
    public func annotationOutputImage(
        _ delegate: AnnotationImageProcessingDelegate, cameraImage: CIImage?,
        segmentationOverlayImage: CIImage?, featureGeometryOverlayImage: CIImage?,
        surfaceAnalysisOverlayImage: CIImage?
    ) {
        if let cameraImage {
            cameraImageView.image = UIImage(ciImage: cameraImage)
        }
        if let segmentationOverlayImage {
            self.segmentationOverlayImageView.image = UIImage(ciImage: segmentationOverlayImage)
        }
        if let featureGeometryOverlayImage {
            self.featureGeometryOverlayImageView.image = UIImage(ciImage: featureGeometryOverlayImage)
        }
        if let surfaceAnalysisOverlayImage {
            self.surfaceAnalysisOverlayImageView.image = UIImage(ciImage: surfaceAnalysisOverlayImage)
        } else {
            surfaceAnalysisOverlayImageView.image = nil
        }
    }

    public func annotationSelectionSpotlightImage(
        _ delegate: AnnotationImageProcessingDelegate,
        selectionSpotlightOverlayImage: CIImage?
    ) {
        if let selectionSpotlightOverlayImage {
            self.selectionSpotlightOverlayImageView.image = UIImage(ciImage: selectionSpotlightOverlayImage)
        } else {
            self.selectionSpotlightOverlayImageView.image = nil
        }
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        annotationImageManager.setOrientation(getOrientation())
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.annotationImageManager.setOrientation(self.getOrientation())
            self.view.layoutIfNeeded()
        })
    }
}

public struct HostedAnnotationImageViewController<Feature: EditableAccessibilityFeature>: UIViewControllerRepresentable{
    public var annotationImageManager: AnnotationImageManager<Feature>
    
    public init(annotationImageManager: AnnotationImageManager<Feature>) {
        self.annotationImageManager = annotationImageManager
    }
    
    public func makeUIViewController(context: Context) -> AnnotationImageViewController<Feature> {
        let vc = AnnotationImageViewController(annotationImageManager: annotationImageManager)
        return vc
    }
    
    public func updateUIViewController(_ uiViewController: AnnotationImageViewController<Feature>, context: Context) {
    }
    
    public static func dismantleUIViewController(_ uiViewController: AnnotationImageViewController<Feature>, coordinator: ()) {
    }
}
