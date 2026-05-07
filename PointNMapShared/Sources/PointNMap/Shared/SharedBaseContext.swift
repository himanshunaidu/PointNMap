//
//  SharedBaseContext.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/24/25.
//
import SwiftUI
import Combine

public final class SharedBaseContext: ObservableObject {
    public var metalContext: MetalContext?
    public var isEnhancedAnalysisEnabled: Bool = false
    
    public func configure() throws {
        metalContext = try MetalContext()
    }
}
