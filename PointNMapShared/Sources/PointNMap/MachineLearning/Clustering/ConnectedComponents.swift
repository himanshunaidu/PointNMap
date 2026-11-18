//
//  ConnectedComponents.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/21/25.
//

/**
    A clustering algorithm that groups values based on their connectivity using a user-defined adjacency function.

    TODO: Move the logic to Metal for performance improvements.
 */
public struct ConnectedComponents<Value: Equatable> {
    private class Point {
        typealias Label = Int

        let value: Value
        var label: Label?

        init(_ value: Value) {
            self.value = value
        }
    }

    private let minimumComponentSize: Int
    private let adjacencyFunction: (Value, Value, Float) throws -> Bool
    private let adjacencyThreshold: Float

    /**
     Initializes the ConnectedComponents clustering algorithm.

     - Parameters:
        - minimumComponentSize: The minimum number of values required for a connected component to be retained.
        - adjacencyFunction: A function that checks if two values are adjacent (connected).
            If they are not, checks if their distance is within a threshold.
        - adjacencyThreshold: The threshold forwarded to the adjacency function.
     */
    public init(
        minimumComponentSize: Int,
        adjacencyFunction: @escaping (Value, Value, Float) throws -> Bool,
        adjacencyThreshold: Float = 0.0
    ) {
        self.minimumComponentSize = minimumComponentSize
        self.adjacencyFunction = adjacencyFunction
        self.adjacencyThreshold = adjacencyThreshold
    }

    @available(*, deprecated, message: "Use init(minimumComponentSize:adjacencyFunction:adjacencyThreshold:) instead.")
    public init(
        minimumNumberOfPoints: Int,
        adjacencyFunction: @escaping (Value, Value, Float) throws -> Bool,
        adjacencyThreshold: Float = 0.0
    ) {
        self.init(
            minimumComponentSize: minimumNumberOfPoints,
            adjacencyFunction: adjacencyFunction,
            adjacencyThreshold: adjacencyThreshold
        )
    }

    /**
     Clusters values according to the specified parameters.

     Components are returned in discovery order. Components smaller than
     ``minimumComponentSize`` are returned as outliers.

     - Parameter values: The values to cluster.
     - Throws: Rethrows any error produced by the adjacency function.
     - Returns: Retained connected components and values from filtered components.
     */
    public func fit(values: [Value]) throws -> (clusters: [[Value]], outliers: [Value]) {
        let points = values.map { Point($0) }
        var clusters: [[Value]] = []
        var outliers: [Value] = []
        var currentLabel = 0

        for seed in points where seed.label == nil {
            seed.label = currentLabel
            var queue = [seed]
            var queueIndex = 0
            var component: [Value] = []

            while queueIndex < queue.count {
                let current = queue[queueIndex]
                queueIndex += 1
                component.append(current.value)

                for candidate in points where candidate.label == nil {
                    if try adjacencyFunction(current.value, candidate.value, adjacencyThreshold) {
                        candidate.label = currentLabel
                        queue.append(candidate)
                    }
                }
            }

            if component.count < minimumComponentSize {
                outliers.append(contentsOf: component)
            } else {
                clusters.append(component)
            }
            currentLabel += 1
        }

        return (clusters, outliers)
    }
}
