import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var selectedImage: UIImage? = nil

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
        inputText = ""
        clearImage()

        // 3. Simuleer AI reactie (Dummy)
        simulateAIResponse()
    }

    private func simulateAIResponse() {
        Task {
            // Wacht 2 seconden
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Voeg dummy AI bericht toe
            let aiMessage = ChatMessage(role: .ai, text: "Ik ben je virtuele coach, hoe ging je training?")
            messages.append(aiMessage)
        }
    }
}
