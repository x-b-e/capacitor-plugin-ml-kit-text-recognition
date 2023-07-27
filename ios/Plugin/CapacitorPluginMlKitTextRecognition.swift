import Foundation
import Capacitor
import Vision

@objc public class CapacitorPluginMlKitTextRecognition: NSObject {
    
    var recognizedText: [String: Any] = [
        "text": "",
        "blocks": []
    ]
    var imageWidth: Double = 0
    var imageHeight: Double = 0
    
    struct Block {
        let lines: [Line]
        var dictionary: [String: Any] {
            return [
                "lines": lines.map{$0.dictionary}
            ]
        }
    }
    
    struct Line {
        let elements: [Element]
        var dictionary: [String: Any] {
            return [
                "elements": elements.map{$0.dictionary}
            ]
        }
    }
    
    struct Element {
        let text: String
        let confidence: Float
        let boundingBox: BoundingBox
        let recognizedLanguage: String
        var dictionary: [String: Any] {
            return [
                "text": text,
                "confidence": confidence,
                "boundingBox": boundingBox.dictionary,
                "recognizedLanguage": recognizedLanguage,
            ]
        }
    }

    struct BoundingBox {
        let left: CGFloat
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        var dictionary: [String: Any] {
            return [
                "left": left,
                "top": top,
                "right": right,
                "bottom": bottom
            ]
        }
    }
    
    
    
    @objc public func recognize(call: CAPPluginCall, languages: Array<String>, cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        // caching image size to convert the bboxes later
        self.imageWidth = Double(cgImage.width)
        self.imageHeight = Double(cgImage.height)
        
        // create the request
        let request = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        request.recognitionLevel = .fast
        request.recognitionLanguages = languages
        
        // create the rerquest handler
        let imageRequestHandler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: orientation,
            options: [:]
        )
        
        // add to the global queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try imageRequestHandler.perform([request])
                call.resolve(self.recognizedText)
            } catch let error as NSError {
                print("Failed to perform image request: \(error)")
                call.reject(error.description)
            }
        }
    }
    
    ///  Transforms the VNRequest to the JS Array with the recognized text
    ///
    ///  - Parameters:
    ///    - request: pointer to the request to the Vision framework, to get the results
    ///    - error: error message if something is wrong
    ///
    ///  - Returns:
    func handleDetectedText(request: VNRequest?, error: Error?) {
        if let error = error {
            NSLog("Error detecting text: \(error)")
            return
        }
        
        guard let observations = request?.results as? [VNRecognizedTextObservation], observations.count > 0 else {
            NSLog("No text found")
            return
        }
        
        var fullText = ""
        
        let textBlocks: [Block] = observations.compactMap { observation in

            // Find the top 5 candidates.
            let candidates = observation.topCandidates(3)
            var seenLines = Set<String>()
            let lines: [Line] = candidates.compactMap { candidate in
                var fullText = candidate.string
                guard !seenLines.contains(fullText) else {
                    return nil
                }
                seenLines.insert(fullText)
                let confidence = candidate.confidence
                
                let words = fullText.components(separatedBy: " ")
                
                let elements: [Element] = words.compactMap { word in
                    let stringRange = word.startIndex..<word.endIndex
                    let wordBoxObservation = try? candidate.boundingBox(for: stringRange)
                    // Get the normalized CGRect value.
                    let boundingBox = wordBoxObservation?.boundingBox ?? .zero
                    
                    // Convert the rectangle from normalized coordinates to image coordinates.
                    let normalizedBox = VNImageRectForNormalizedRect(boundingBox,
                                                                    Int(self.imageWidth),
                                                                    Int(self.imageHeight))
                    
                    
                    return Element(text: word, confidence: confidence, boundingBox: BoundingBox(left: normalizedBox.minX, top: normalizedBox.maxY, right: normalizedBox.maxX, bottom: normalizedBox.minY), recognizedLanguage: "eng")
                }
                
                let line = Line(elements: elements)
                
                return line
            }
            
            return Block(lines: lines)
        }
        
        self.recognizedText = [
            "text": fullText,
            "blocks": textBlocks.map{$0.dictionary}
        ]
        
    }
    
    /// Convert Vision coordinates to pixel coordinates within image.
    ///
    /// - Parameters:
    ///   - boundingBox: The bounding box returned by Vision framework.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///
    /// - Returns: The bounding box in pixel coordinates within the initial image.
    
    func convertBbox(boundingBox: CGRect, width imageWidth: Double, height imageHeight: Double) -> [String : CGFloat] {
        // Begin with input rect.
        var rect = boundingBox
        
        // Reposition origin.
        rect.origin.x *= imageWidth
        rect.origin.y = (1 - rect.maxY) * imageHeight
        
        // Rescale normalized coordinates.
        rect.size.width *= imageWidth
        rect.size.height *= imageHeight
        
        let bbox = [
            "x0": rect.origin.x,
            "y0": rect.origin.y,
            "x1": rect.origin.x + rect.size.width,
            "y1": rect.origin.y + rect.size.height
        ]
        return bbox
    }
}
