import SwiftUI
import AVFoundation
import MediaPipeTasksVision
import UIKit
import Starscream

// MARK: - Main App View
struct ContentView: View {
    @State private var isShowingHomeScreen = true
    
    var body: some View {
        if isShowingHomeScreen {
            HomeScreenView(onStartSwinging: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isShowingHomeScreen = false
                }
            })
        } else {
            SwingAnalysisView(onBackPressed: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isShowingHomeScreen = true
                }
            })
        }
    }
}
