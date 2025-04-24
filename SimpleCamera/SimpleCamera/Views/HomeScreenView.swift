import SwiftUI

struct HomeScreenView: View {
    var onStartSwinging: () -> Void
    @State private var isButtonAnimating = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(#colorLiteral(red: 0.1019607857, green: 0.2784313858, blue: 0.400000006, alpha: 1)), Color(#colorLiteral(red: 0.09019608051, green: 0.1921568662, blue: 0.2549019754, alpha: 1))]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            // Animated background elements (golf ball effect)
            ForEach(0..<20) { index in
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: CGFloat.random(in: 20...100))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // App title
                VStack(spacing: 12) {
                    Text("SWING")
                        .font(.system(size: 60, weight: .heavy))
                        .foregroundColor(.white)
                    
                    Text("ANALYSER")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1)))
                }
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Spacer()
                
                // Subtitle
                Text("Improve your swing with\nreal-time pose analysis")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                
                Spacer()
                
                // Start button
                Button(action: onStartSwinging) {
                    Text("START SWINGING")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 40)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1)))
                                .shadow(color: Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1)).opacity(0.5), radius: 8, x: 0, y: 4)
                        )
                        .scaleEffect(isButtonAnimating ? 1.05 : 1.0)
                }
                .onAppear {
                    // Subtle button animation to draw attention
                    withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isButtonAnimating = true
                    }
                }
                
                Spacer()
                
                // Footer text
                Text("Powered by MediaPipe & AI")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 20)
            }
            .padding()
        }
    }
} 