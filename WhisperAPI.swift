import Foundation
import AVFoundation

class WhisperAPI {
    private let OPENAI_API_KEY = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
    private let maxRetries = 3
    
    enum WhisperError: Error {
        case noAPIKey
        case invalidResponse
        case networkError(Error)
        case fileNotFound
    }
    
    func transcribe(audioFileURL: URL, completion: @escaping (String?) -> Void) {
        guard !OPENAI_API_KEY.isEmpty else {
            print("OpenAI API key not found")
            completion(nil)
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            print("Audio file not found at: \(audioFileURL.path)")
            completion(nil)
            return
        }
        
        sendToWhisper(fileURL: audioFileURL, retryCount: 0, completion: completion)
    }
    
    // Legacy method for backwards compatibility
    func recordAndTranscribe(completion: @escaping (String?) -> Void) {
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let tempDir = FileManager.default.temporaryDirectory
        let audioFile = tempDir.appendingPathComponent("speech.m4a")

        do {
            let file = try AVAudioFile(forWriting: audioFile, settings: format.settings)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { (buffer, time) in
                try? file.write(from: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.transcribe(audioFileURL: audioFile, completion: completion)
            }
        } catch {
            print("Failed to setup recording: \(error)")
            completion(nil)
        }
    }

    private func sendToWhisper(fileURL: URL, retryCount: Int, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let boundary = UUID().uuidString

        request.setValue("Bearer \(OPENAI_API_KEY)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        do {
            var data = Data()
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\n")
            data.append("Content-Type: audio/m4a\r\n\r\n")
            data.append(try Data(contentsOf: fileURL))
            data.append("\r\n--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n")
            data.append("Content-Disposition: form-data; name=\"language\"\r\n\r\nen\r\n")
            data.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n0.2\r\n")
            data.append("--\(boundary)--\r\n")

            request.httpBody = data
        } catch {
            print("Failed to read audio file: \(error)")
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] responseData, response, error in
            if let error = error {
                print("Network error: \(error)")
                if retryCount < self?.maxRetries ?? 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self?.sendToWhisper(fileURL: fileURL, retryCount: retryCount + 1, completion: completion)
                    }
                } else {
                    completion(nil)
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Whisper API Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 429 { // Rate limited
                    if retryCount < self?.maxRetries ?? 0 {
                        let delay = pow(2.0, Double(retryCount)) // Exponential backoff
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self?.sendToWhisper(fileURL: fileURL, retryCount: retryCount + 1, completion: completion)
                        }
                        return
                    }
                }
            }
            
            guard let data = responseData else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    // Clean up the transcription
                    let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(cleanedText.isEmpty ? nil : cleanedText)
                } else {
                    print("Invalid response format")
                    completion(nil)
                }
            } catch {
                print("JSON parsing error: \(error)")
                completion(nil)
            }
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: fileURL)
            
        }.resume()
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
} 