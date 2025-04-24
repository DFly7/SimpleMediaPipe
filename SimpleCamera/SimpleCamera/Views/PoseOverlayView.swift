import SwiftUI

struct PoseOverlayView: View {
    var poseResults: [PoseLandmark]
    
    // Define different body part groups with different colors
    let connectionGroups: [(connections: [(fromIndex: Int, toIndex: Int)], color: Color)] = [
        // Face oval - light blue
        ([(0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8)], Color(red: 0.2, green: 0.8, blue: 1.0)),
        
        // Left arm - gold
        ([(11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19)], Color(red: 0.9, green: 0.7, blue: 0.0)),
        
        // Right arm - green
        ([(12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20)], Color(red: 0.0, green: 0.8, blue: 0.2)),
        
        // Torso - purple
        ([(11, 12), (11, 23), (12, 24), (23, 24)], Color(red: 0.8, green: 0.2, blue: 0.8)),
        
        // Left leg - red
        ([(23, 25), (25, 27), (27, 29), (27, 31), (29, 31)], Color(red: 0.9, green: 0.2, blue: 0.2)),
        
        // Right leg - blue
        ([(24, 26), (26, 28), (28, 30), (28, 32), (30, 32)], Color(red: 0.2, green: 0.4, blue: 0.9))
    ]
    
    // Define different landmark types with specific styles
    func landmarkStyle(for index: Int) -> (color: Color, size: CGFloat) {
        // Face landmarks (smaller, orange)
        if index <= 10 {
            return (Color.orange, 6)
        }
        
        // Wrist landmarks (medium, bright red)
        else if index == 15 || index == 16 {
            return (Color.red.opacity(0.9), 8)
        }
        
        // Hip landmarks (larger, purple)
        else if index == 23 || index == 24 {
            return (Color.purple, 10)
        }
        
        // Other landmarks (medium, white)
        else {
            return (Color.white, 7)
        }
    }
    
    // Check if we have valid landmarks to draw - strict version with no delay
    private func hasValidPose() -> Bool {
        // Check if we have enough landmarks
        guard !poseResults.isEmpty && poseResults.count >= 33 else {
            return false
        }
        
        // Require BOTH shoulders to be visible with high confidence
        let leftShoulderVisible = poseResults[11].visibility > 0.7
        let rightShoulderVisible = poseResults[12].visibility > 0.7
        
        // Require at least both shoulders to be visible
        return (leftShoulderVisible && rightShoulderVisible)
    }
    
    // Create a custom connection struct to handle z-ordering
    private struct Connection: Identifiable, Comparable {
        let id = UUID()
        let fromIndex: Int
        let toIndex: Int
        let color: Color
        let zValue: CGFloat
        let groupIndex: Int
        
        // Implement Comparable to sort by z-value
        static func < (lhs: Connection, rhs: Connection) -> Bool {
            // Negative comparison because larger z values are further away
            return lhs.zValue > rhs.zValue
        }
        
        // Implement Equatable
        static func == (lhs: Connection, rhs: Connection) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    // Create a custom landmark struct to handle z-ordering
    private struct DrawableLandmark: Identifiable, Comparable {
        let id = UUID()
        let originalIndex: Int
        let position: CGPoint
        let style: (color: Color, size: CGFloat)
        let zValue: CGFloat
        
        // Implement Comparable to sort by z-value
        static func < (lhs: DrawableLandmark, rhs: DrawableLandmark) -> Bool {
            // Negative comparison because larger z values are further away
            return lhs.zValue > rhs.zValue
        }
        
        // Implement Equatable
        static func == (lhs: DrawableLandmark, rhs: DrawableLandmark) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if !poseResults.isEmpty && hasValidPose() {
                ZStack {
                    // Prepare all connections with z-order information
                    let sortedConnections = prepareConnectionsWithDepth(geometry: geometry)
                    
                    // Draw connections in z-order (from back to front)
                    ForEach(sortedConnections) { connection in
                        if connection.fromIndex < poseResults.count && connection.toIndex < poseResults.count {
                            let fromLandmark = poseResults[connection.fromIndex]
                            let toLandmark = poseResults[connection.toIndex]
                            
                            // Only draw connections if both landmarks have reasonable visibility
                            if fromLandmark.visibility > 0.2 && toLandmark.visibility > 0.2 {
                                // Calculate positions
                                let fromPoint = CGPoint(
                                    x: fromLandmark.x * geometry.size.width,
                                    y: fromLandmark.y * geometry.size.height
                                )
                                let toPoint = CGPoint(
                                    x: toLandmark.x * geometry.size.width,
                                    y: toLandmark.y * geometry.size.height
                                )
                                
                                // Draw connection with proper styling and anti-aliasing
                                Path { path in
                                    path.move(to: fromPoint)
                                    path.addLine(to: toPoint)
                                }
                                .stroke(connection.color, style: StrokeStyle(
                                    lineWidth: 4,
                                    lineCap: .round,
                                    lineJoin: .round
                                ))
                                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    
                    // Prepare landmarks with z-order information
                    let sortedLandmarks = prepareLandmarksWithDepth(geometry: geometry)
                    
                    // Draw landmarks in z-order (from back to front)
                    ForEach(sortedLandmarks) { landmark in
                        ZStack {
                            // Outer glow effect
                            Circle()
                                .fill(landmark.style.color.opacity(0.4))
                                .frame(width: landmark.style.size + 4, height: landmark.style.size + 4)
                            
                            // Inner solid circle
                            Circle()
                                .fill(landmark.style.color)
                                .frame(width: landmark.style.size, height: landmark.style.size)
                                .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 0)
                        }
                        .position(landmark.position)
                    }
                }
            } else {
                // Empty view when no pose is detected
                EmptyView()
            }
        }
    }
    
    // Helper function to prepare connections with depth information
    private func prepareConnectionsWithDepth(geometry: GeometryProxy) -> [Connection] {
        var connections: [Connection] = []
        
        for (groupIndex, group) in connectionGroups.enumerated() {
            for connection in group.connections {
                if connection.fromIndex < poseResults.count && connection.toIndex < poseResults.count {
                    let fromLandmark = poseResults[connection.fromIndex]
                    let toLandmark = poseResults[connection.toIndex]
                    
                    if fromLandmark.visibility > 0.2 && toLandmark.visibility > 0.2 {
                        // Calculate average z-value for the connection
                        let avgZ = (fromLandmark.z + toLandmark.z) / 2
                        
                        connections.append(Connection(
                            fromIndex: connection.fromIndex,
                            toIndex: connection.toIndex,
                            color: group.color,
                            zValue: avgZ,
                            groupIndex: groupIndex
                        ))
                    }
                }
            }
        }
        
        // Sort by z-value (smaller z is closer to camera)
        return connections.sorted()
    }
    
    // Helper function to prepare landmarks with depth information
    private func prepareLandmarksWithDepth(geometry: GeometryProxy) -> [DrawableLandmark] {
        var landmarks: [DrawableLandmark] = []
        
        for landmark in poseResults {
            if landmark.visibility > 0.3 {
                let style = landmarkStyle(for: landmark.id)
                let position = CGPoint(
                    x: landmark.x * geometry.size.width,
                    y: landmark.y * geometry.size.height
                )
                
                landmarks.append(DrawableLandmark(
                    originalIndex: landmark.id,
                    position: position,
                    style: style,
                    zValue: landmark.z
                ))
            }
        }
        
        // Sort by z-value (smaller z is closer to camera)
        return landmarks.sorted()
    }
} 