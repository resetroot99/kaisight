import Foundation
import UIKit

class GPTManager {
    
    // note: Add your OpenAI API key here
    private let OPENAI_API_KEY = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
    private let maxRetries = 3
    
    enum GPTError: Error {
        case noAPIKey
        case invalidResponse
        case networkError(Error)
        case imageProcessingError
    }
    
    func ask(prompt: String, image: UIImage?, completion: @escaping (String) -> Void) {
        guard !OPENAI_API_KEY.isEmpty else {
            completion("I'm sorry, but the API key is not configured. Please check the app settings.")
            return
        }
        
        sendRequest(prompt: prompt, image: image, retryCount: 0, completion: completion)
    }
    
    private func sendRequest(prompt: String, image: UIImage?, retryCount: Int, completion: @escaping (String) -> Void) {
        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": """
                You are an AI assistant specifically designed to help blind and visually impaired users. 
                
                Your responses should be:
                - Clear and descriptive
                - Focused on relevant details for navigation and safety
                - Spoken in natural, conversational language
                - Include spatial relationships (left, right, in front, behind)
                - Mention colors, text, people, objects, and potential obstacles
                - Keep responses concise but informative (2-3 sentences max)
                - If asked about reading text, read it exactly as written
                - For navigation questions, provide step-by-step directions
                - Always prioritize safety-related information
                
                Remember: This person cannot see, so describe what they need to know to understand their environment.
                """
            ]
        ]
        
        // Process and add the user message with image if available
        if let image = image,
           let processedImageData = processImageForAPI(image) {
            messages.append([
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": "User question: \(prompt)\n\nPlease analyze the image and help answer their question. Focus on details relevant to someone who cannot see."
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(processedImageData)",
                            "detail": "high"
                        ]
                    ]
                ]
            ])
        } else {
            messages.append([
                "role": "user",
                "content": "User question: \(prompt)\n\nNote: No image was captured with this request."
            ])
        }
        
        let body: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": messages,
            "max_tokens": 300,
            "temperature": 0.3
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(OPENAI_API_KEY)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("I'm sorry, I couldn't process your request due to a technical error.")
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                if retryCount < self?.maxRetries ?? 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self?.sendRequest(prompt: prompt, image: image, retryCount: retryCount + 1, completion: completion)
                    }
                } else {
                    completion("I'm sorry, I'm having trouble connecting right now. Please try again.")
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                
                if httpResponse.statusCode == 429 { // Rate limited
                    if retryCount < self?.maxRetries ?? 0 {
                        let delay = pow(2.0, Double(retryCount))
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self?.sendRequest(prompt: prompt, image: image, retryCount: retryCount + 1, completion: completion)
                        }
                        return
                    }
                }
                
                if httpResponse.statusCode >= 400 {
                    completion("I'm sorry, I encountered an error while processing your request. Please try again.")
                    return
                }
            }
            
            guard let data = data else {
                completion("I'm sorry, I didn't receive a response. Please try again.")
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                if let reply = decoded.choices.first?.message.content {
                    completion(reply)
                } else {
                    completion("I'm sorry, I couldn't understand the response. Please try again.")
                }
            } catch {
                completion("I'm sorry, there was an error processing the response. Please try again.")
            }
        }.resume()
    }
    
    private func processImageForAPI(_ image: UIImage) -> String? {
        // Resize image to reduce API costs while maintaining quality
        let targetSize = CGSize(width: 1024, height: 1024)
        let resizedImage = resizeImage(image, to: targetSize)
        
        // Compress to JPEG with good quality
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        return imageData.base64EncodedString()
    }
    
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? image
    }
    
    struct OpenAIResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable { 
                let content: String 
            }
            let message: Message
        }
        let choices: [Choice]
    }
} 