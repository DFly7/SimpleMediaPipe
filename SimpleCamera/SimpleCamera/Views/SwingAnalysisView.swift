import SwiftUI
import AVFoundation

struct SwingAnalysisView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var socketManager = WebSocketManager()
    @State private var isCameraActive = false
    @State private var showPermissionAlert = false
    @State private var lastScore: Int = 0
    @State private var showControls = true
    @State private var showBottomPanel = true
    @State private var showPoseOverlay = true
    @State private var scoreTimer: Timer? = nil
    var onBackPressed: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Professional dark background
                Color(#colorLiteral(red: 0.05882352941, green: 0.09019607843, blue: 0.1098039216, alpha: 1)).edgesIgnoringSafeArea(.all)
                
                // Full-screen camera view, always fills the entire screen
                ZStack {
                    // Camera preview (only shown when active)
                    if isCameraActive {
                        CameraPreviewView(session: cameraManager.session)
                            .overlay(
                                // Pose overlay view (only show if enabled)
                                showPoseOverlay ? PoseOverlayView(poseResults: cameraManager.poseResults) : nil
                            )
                            .edgesIgnoringSafeArea(.all)
                    } else {
                        // Placeholder when camera is off
                        ZStack {
                            Color(#colorLiteral(red: 0.1298420429, green: 0.1298461258, blue: 0.1298439503, alpha: 1)).edgesIgnoringSafeArea(.all)
                            VStack(spacing: 20) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text("Camera Off")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    
                                Text("Tap 'Start Analysis' to begin")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    
                    // Overlay elements that stay on top of camera view
                    VStack {
                        // Semi-transparent top status bar
                        HStack {
                            // Back button
                            Button(action: onBackPressed) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Home")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                            }
                            
                            Spacer()
                            
                            // Toggle bottom panel button
                            Button(action: {
                                withAnimation(.spring()) {
                                    showBottomPanel.toggle()
                                }
                            }) {
                                Image(systemName: showBottomPanel ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            // Connection status with subtle background
                            if socketManager.isConnected {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Connected")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                            } else {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("Not Connected")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.1))
                        
                        // Score display at top center
                        if lastScore > 0 {
                            VStack(spacing: 4) {
                                // Score header
                                Text("SWING SCORE")
                                    .font(.system(size: 12, weight: .heavy))
                                    .tracking(1.5)
                                    .foregroundColor(.white.opacity(0.9))
                                
                                // Score value
                                Text("\(lastScore)")
                                    .font(.system(size: 48, weight: .heavy))
                                    .foregroundColor(scoreColor(for: lastScore))
                                
                                // Score description
                                Text(scoreDescription(for: lastScore))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 24)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.black.opacity(0.7))
                                    .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
                            )
                            .padding(.top, 20)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        
                        Spacer()
                        
                        // Analyzing indicator when active (ONLY shown if camera is active)
                        if isCameraActive && !showBottomPanel {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                    .opacity(sin(Date().timeIntervalSince1970 * 2) > 0 ? 1 : 0.3) // Blinking effect
                                
                                Text("ANALYSING")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                
                // Bottom control panel (slides in/out)
                if showBottomPanel {
                    VStack {
                        Spacer()
                        
                        ZStack {
                            // Semi-transparent background
                            Color(#colorLiteral(red: 0.09803921569, green: 0.1294117647, blue: 0.1490196078, alpha: 1))
                                .edgesIgnoringSafeArea(.bottom)
                            
                            VStack(spacing: 20) {
                                // Tools and options
                                HStack {
                                    Spacer()
                                    
                                    // Reconnect button
                                    VStack(spacing: 6) {
                                        Button(action: {
                                            socketManager.reconnect()
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.blue.opacity(0.2))
                                                    .frame(width: 48, height: 48)
                                                
                                                Image(systemName: "arrow.triangle.2.circlepath")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        Text("Reconnect")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    // Add camera flip button
                                    VStack(spacing: 6) {
                                        Button(action: {
                                            cameraManager.toggleCamera()
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.purple.opacity(0.2))
                                                    .frame(width: 48, height: 48)
                                                
                                                Image(systemName: "camera.rotate")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.purple)
                                            }
                                        }
                                        .disabled(!isCameraActive)
                                        .opacity(isCameraActive ? 1.0 : 0.5)
                                        Text("Flip Camera")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    // Primary analysis control
                                    VStack(spacing: 10) {
                                        ZStack {
                                            // Outer ring
                                            Circle()
                                                .stroke(
                                                    isCameraActive ? Color.red : Color.green,
                                                    lineWidth: 4
                                                )
                                                .frame(width: 74, height: 74)
                                            
                                            // Inner button
                                            Button(action: isCameraActive ? stopCamera : startCamera) {
                                                Circle()
                                                    .fill(isCameraActive ? Color.red : Color.green)
                                                    .frame(width: 60, height: 60)
                                                    .overlay(
                                                        ZStack {
                                                            if isCameraActive {
                                                                RoundedRectangle(cornerRadius: 4)
                                                                    .fill(Color.white)
                                                                    .frame(width: 20, height: 20)
                                                            } else {
                                                                Circle()
                                                                    .stroke(Color.white, lineWidth: 2)
                                                                    .frame(width: 22, height: 22)
                                                            }
                                                        }
                                                    )
                                            }
                                        }
                                        Text(isCameraActive ? "Stop" : "Start Analysis")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    
                                    Spacer()
                                    
                                    // Toggle controls visibility button
                                    VStack(spacing: 6) {
                                        Button(action: {
                                            withAnimation(.spring()) {
                                                showControls.toggle()
                                            }
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(white: 0.3, opacity: 0.2))
                                                    .frame(width: 48, height: 48)
                                                
                                                Image(systemName: "slider.horizontal.3")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Text("Controls")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 20)
                                
                                // Analysing indicator in bottom panel when active
                                if isCameraActive {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 12, height: 12)
                                            .opacity(sin(Date().timeIntervalSince1970 * 2) > 0 ? 1 : 0.3) // Blinking effect
                                        
                                        Text("ANALYSING")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(20)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                
                                // Session info and messages
                                if showControls {
                                    VStack(spacing: 18) {
                                        Divider()
                                            .background(Color.white.opacity(0.2))
                                            .padding(.horizontal, 40)
                                        
                                        // Toggle for Pose Overlay
                                        Button(action: {
                                            withAnimation {
                                                showPoseOverlay.toggle()
                                            }
                                        }) {
                                            HStack {
                                                // Text and icon for the toggle
                                                HStack(spacing: 10) {
                                                    Image(systemName: "figure.stand")
                                                        .font(.system(size: 15))
                                                        .foregroundColor(.white)
                                                    
                                                    Text("Pose Overlay")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.white)
                                                }
                                                
                                                Spacer()
                                                
                                                // Custom toggle indicator
                                                ZStack {
                                                    Capsule()
                                                        .fill(showPoseOverlay ? Color.green.opacity(0.5) : Color.gray.opacity(0.5))
                                                        .frame(width: 50, height: 26)
                                                    
                                                    Circle()
                                                        .fill(showPoseOverlay ? Color.green : Color.gray)
                                                        .frame(width: 22, height: 22)
                                                        .offset(x: showPoseOverlay ? 12 : -12)
                                                        .animation(.spring(), value: showPoseOverlay)
                                                }
                                            }
                                            .padding(.horizontal, 30)
                                            .padding(.vertical, 12)
                                            .background(Color.black.opacity(0.2))
                                            .cornerRadius(12)
                                            .padding(.horizontal, 20)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        Divider()
                                            .background(Color.white.opacity(0.2))
                                            .padding(.horizontal, 40)
                                            .padding(.vertical, 5)
                                    }
                                }
                            }
                        }
                        .frame(height: geometry.size.height * 0.30)
                        .transition(.move(edge: .bottom))
                    }
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            setupCamera()
            // Set up the score observation
            setupScoreObserver()
        }
        .onDisappear {
            socketManager.disconnect()
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Camera Permission Required"),
                message: Text("This app needs camera access to function. Please enable it in Settings."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // Function to determine score color based on score value
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 0...30:
            return Color(#colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1))
        case 31...70:
            return Color(#colorLiteral(red: 0.9529411793, green: 0.6862745285, blue: 0.1333333403, alpha: 1))
        default:
            return Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1))
        }
    }
    
    // Function to get score description
    private func scoreDescription(for score: Int) -> String {
        switch score {
        case 0...30:
            return "Needs improvement"
        case 31...70:
            return "Good technique"
        default:
            return "Excellent form!"
        }
    }
    
    // Setup observer for score updates
    private func setupScoreObserver() {
        // Observe when score changes
        socketManager.onScoreReceived = { score in
            withAnimation(.spring()) {
                self.lastScore = score
                
                // Cancel any existing timer
                self.scoreTimer?.invalidate()
                
                // Create a new timer to clear the score after 10 seconds
                self.scoreTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    withAnimation(.spring()) {
                        self.lastScore = 0
                    }
                }
            }
        }
    }
    
    private func setupCamera() {
        cameraManager.requestPermission { granted in
            if granted {
                cameraManager.setup()
                // Connect the socket manager to the camera manager
                cameraManager.setSocketManager(socketManager)
            } else {
                showPermissionAlert = true
            }
        }
    }
    
    private func startCamera() {
        withAnimation {
            cameraManager.startCapture()
            isCameraActive = true
        }
    }
    
    private func stopCamera() {
        withAnimation {
            // Notify the server that camera is being stopped
            socketManager.sendStopNotification()
            
            // Then stop the camera capture
            cameraManager.stopCapture()
            isCameraActive = false
        }
    }
} 