import Vision
import UIKit

actor OCRService {
    static let shared = OCRService()
    
    func recognizeText(from image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Get top candidates
                let text = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func extractExpirationDate(from textLines: [String]) -> Date? {
        let fullText = textLines.joined(separator: "\n")
        
        // Use NSDataDetector for dates
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        
        let matches = detector.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
        
        // Filter for future dates or recent past (to avoid detecting "2020" as a date if it's part of a barcode or something)
        // Also prioritize dates that look like expiration dates (future)
        
        for match in matches {
            if let date = match.date {
                // Basic sanity check: Date should be between 1 year ago and 10 years in future
                let now = Date()
                let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!
                let tenYearsFuture = Calendar.current.date(byAdding: .year, value: 10, to: now)!
                
                if date > oneYearAgo && date < tenYearsFuture {
                    return date
                }
            }
        }
        
        return nil
    }
}
