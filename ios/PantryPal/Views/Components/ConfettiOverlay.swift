import SwiftUI

struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var lastSpawnTime: Date = .distantPast
    
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    
                    // Draw each particle
                    for particle in particles {
                        let age = now - particle.birthTime
                        let x = particle.x + particle.vx * age
                        var y = particle.y + particle.vy * age + 0.5 * 300 * age * age // gravity
                        
                        // Land at bottom and stop
                        let groundY = size.height - particle.size / 2
                        if y >= groundY {
                            y = groundY
                            // Add slight settling effect
                            let settleTime = max(0, age - particle.landTime)
                            if settleTime < 0.3 {
                                y = groundY + sin(settleTime * 10) * 2 * (1 - settleTime / 0.3)
                            }
                        }
                        
                        // Rotation slows down when landed
                        let rotationSpeed = y >= groundY ? particle.rotationSpeed * 0.1 : particle.rotationSpeed
                        let rotation = Angle(degrees: particle.rotation + rotationSpeed * age)
                        
                        var particleContext = context
                        particleContext.translateBy(x: x, y: y)
                        particleContext.rotate(by: rotation)
                        
                        switch particle.shape {
                        case .rectangle:
                            let rect = CGRect(x: -particle.size/2, y: -particle.size/2, 
                                            width: particle.size, height: particle.size * 0.6)
                            particleContext.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(particle.color))
                        case .circle:
                            let rect = CGRect(x: -particle.size/2, y: -particle.size/2, 
                                            width: particle.size, height: particle.size)
                            particleContext.fill(Path(ellipseIn: rect), with: .color(particle.color))
                        case .triangle:
                            let path = Path { p in
                                p.move(to: CGPoint(x: 0, y: -particle.size/2))
                                p.addLine(to: CGPoint(x: particle.size/2, y: particle.size/2))
                                p.addLine(to: CGPoint(x: -particle.size/2, y: particle.size/2))
                                p.closeSubpath()
                            }
                            particleContext.fill(path, with: .color(particle.color))
                        }
                    }
                }
                .onChange(of: timeline.date) { _, newDate in
                    updateParticles(date: newDate, size: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            startSpawning()
        }
    }
    
    private func startSpawning() {
        // Initial burst of particles
        particles = []
        lastSpawnTime = Date()
    }
    
    private func updateParticles(date: Date, size: CGSize) {
        let now = date.timeIntervalSinceReferenceDate
        
        // Don't remove particles anymore - let them accumulate at bottom
        // Only update land times
        for i in 0..<particles.count {
            let age = now - particles[i].birthTime
            let y = particles[i].y + particles[i].vy * age + 0.5 * 300 * age * age
            let groundY = size.height - particles[i].size / 2
            
            if y >= groundY && particles[i].landTime == 0 {
                particles[i].landTime = age
            }
        }
        
        // Spawn new particles periodically
        let timeSinceLastSpawn = date.timeIntervalSince(lastSpawnTime)
        if timeSinceLastSpawn > 0.08 && particles.count < 120 {
            spawnParticles(count: 12, size: size, time: now)
            lastSpawnTime = date
        }
    }
    
    private func spawnParticles(count: Int, size: CGSize, time: TimeInterval) {
        let colors: [Color] = [
            Color(red: 0.6, green: 0.3, blue: 0.8),  // Purple
            Color(red: 1.0, green: 0.5, blue: 0.2),  // Orange
            Color(red: 0.3, green: 0.8, blue: 0.5),  // Green
            Color(red: 1.0, green: 0.8, blue: 0.2),  // Yellow
            Color(red: 0.2, green: 0.6, blue: 1.0),  // Blue
            Color(red: 1.0, green: 0.3, blue: 0.5),  // Pink
        ]
        
        let shapes: [ConfettiShape] = [.rectangle, .circle, .triangle]
        
        for _ in 0..<count {
            let particle = ConfettiParticle(
                id: UUID(),
                x: Double.random(in: 0...size.width),
                y: -20, // Start just above screen
                vx: Double.random(in: -30...30),
                vy: Double.random(in: 50...150),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -180...180),
                size: Double.random(in: 6...12),
                color: colors.randomElement()!,
                shape: shapes.randomElement()!,
                birthTime: time
            )
            particles.append(particle)
        }
    }
}

enum ConfettiShape {
    case rectangle
    case circle
    case triangle
}

struct ConfettiParticle: Identifiable {
    let id: UUID
    let x: Double
    let y: Double
    let vx: Double
    let vy: Double
    let rotation: Double
    let rotationSpeed: Double
    let size: Double
    let color: Color
    let shape: ConfettiShape
    let birthTime: TimeInterval
    var landTime: TimeInterval = 0
}

#Preview("Confetti Celebration") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        ConfettiOverlay()
        
        VStack {
            Spacer()
            Text("🎉 Confetti Preview")
                .font(.title)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

