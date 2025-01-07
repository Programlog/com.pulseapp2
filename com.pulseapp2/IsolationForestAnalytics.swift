import Foundation

class IsolationForestAnalytics {
    private let numTrees: Int
    private let subsampleSize: Int
    private let maxTreeHeight: Int
    
    class IsolationTree {
        var splitValue: Double?
        weak var leftChild: IsolationTree?
        weak var rightChild: IsolationTree?
        var height: Int
        var size: Int
        
        init(height: Int, size: Int) {
            self.height = height
            self.size = size
        }
    }
    
    init(numTrees: Int = 100, subsampleSize: Int = 256) {
        self.numTrees = numTrees
        self.subsampleSize = subsampleSize
        self.maxTreeHeight = Int(ceil(log2(Double(subsampleSize))))
    }
    
    // Build isolation forest from heart rate data
    func buildForest(data: [Double]) -> [IsolationTree] {
        var forest: [IsolationTree] = []
        
        for _ in 0..<numTrees {
            let subsample = data.shuffled().prefix(subsampleSize)
            let tree = buildTree(Array(subsample), height: 0)
            forest.append(tree)
        }
        
        return forest
    }
    
    // Build single isolation tree
    private func buildTree(_ data: [Double], height: Int) -> IsolationTree {
        let tree = IsolationTree(height: height, size: data.count)
        
        // Stop conditions
        if height >= maxTreeHeight || data.count <= 1 {
            return tree
        }
        
        // Find split value
        if let minVal = data.min(), let maxVal = data.max() {
            tree.splitValue = Double.random(in: minVal...maxVal)
            
            let leftData = data.filter { $0 < tree.splitValue! }
            let rightData = data.filter { $0 >= tree.splitValue! }
            
            tree.leftChild = buildTree(leftData, height: height + 1)
            tree.rightChild = buildTree(rightData, height: height + 1)
        }
        
        return tree
    }
    
    // Calculate anomaly score for a value
    func calculateAnomalyScore(_ value: Double, forest: [IsolationTree]) -> Double {
        let pathLengths = forest.map { tree in
            return pathLength(value, tree: tree, currentLength: 0)
        }
        
        let avgPathLength = pathLengths.reduce(0.0, +) / Double(pathLengths.count)
        let normalizedScore = pow(2, -avgPathLength / averagePathLength(subsampleSize))
        
        return normalizedScore
    }
    
    // Calculate path length for a value in a tree
    private func pathLength(_ value: Double, tree: IsolationTree, currentLength: Double) -> Double {
        if tree.leftChild == nil || tree.rightChild == nil {
            return currentLength + averagePathLength(tree.size)
        }
        
        if let splitValue = tree.splitValue {
            if value < splitValue {
                return pathLength(value, tree: tree.leftChild!, currentLength: currentLength + 1)
            } else {
                return pathLength(value, tree: tree.rightChild!, currentLength: currentLength + 1)
            }
        }
        
        return currentLength
    }
    
    // Helper function for average path length calculation
    private func averagePathLength(_ size: Int) -> Double {
        if size <= 1 { return 0 }
        let harmonic = (0..<size-1).reduce(0.0) { $0 + 1.0/Double($1+1) }
        return 2.0 * harmonic - (2.0 * Double(size - 1) / Double(size))
    }
    
    // Detect anomalies in heart rate data
    func detectAnomalies(historicalData: [Double], currentValue: Double, threshold: Double = 0.6) -> Bool {
        let forest = buildForest(data: historicalData)
        let anomalyScore = calculateAnomalyScore(currentValue, forest: forest)
        return anomalyScore > threshold
    }
}
