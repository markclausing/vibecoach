import Foundation
import SwiftUI
import Combine
import GoogleGenerativeAI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var selectedImage: UIImage? = nil
    @Published var isTyping: Bool = false

    // De AI model instantie
    private lazy var model: GenerativeModel = {
        let systemInstruction = "Jij bent een motiverende, deskundige persoonlijke fitness- en wielrencoach. Je helpt de gebruiker met het analyseren van trainingen en data van Strava/Intervals.icu. Houd je antwoorden beknopt, direct, deskundig en enthousiast."

        return GenerativeModel(
            name: "gemini-3.1-pro-preview",
            apiKey: Secrets.geminiAPIKey,
            systemInstruction: ModelContent(role: "system", parts: [.text(systemInstruction)])
        )
    }()

    func clearImage() {
        self.selectedImage = nil
    }

    func sendMessage() {
        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageToSend = selectedImage

        guard !textToSend.isEmpty || imageToSend != nil else { return }

        // 1. Maak bericht aan van gebruiker
        let imageData = imageToSend?.jpegData(compressionQuality: 0.8)
        let userMessage = ChatMessage(role: .user, text: textToSend, attachedImageData: imageData)

        // 2. Voeg toe aan UI en reset velden
        messages.append(userMessage)

        // 3. Haal AI reactie op
        fetchAIResponse(for: textToSend, image: imageToSend)

        inputText = ""
        clearImage()
    }

    private func fetchAIResponse(for text: String, image: UIImage?) {
        guard Secrets.geminiAPIKey != "VUL_HIER_JE_API_KEY_IN" else {
            // Als de API-key ontbreekt, waarschuw dan in de chat.
            messages.append(ChatMessage(role: .ai, text: "Let op: De API-sleutel ontbreekt in Secrets.swift. Vul deze in om met mij te kunnen praten!"))
            return
        }

        isTyping = true

        Task {
            do {
                var contentParts: [ModelContent.Part] = []

                if !text.isEmpty {
                    contentParts.append(.text(text))
                }

                if let image = image, let jpegData = image.jpegData(compressionQuality: 0.8) {
                    contentParts.append(.data(mimetype: "image/jpeg", jpegData))
                }

                let response = try await model.generateContent([ModelContent(role: "user", parts: contentParts)])
                let responseText = response.text ?? "Ik kon geen antwoord genereren."

                messages.append(ChatMessage(role: .ai, text: responseText))
            } catch {
                messages.append(ChatMessage(role: .ai, text: "Sorry, er ging iets mis: \(error.localizedDescription)"))
            }

            isTyping = false
        }
    }
}
