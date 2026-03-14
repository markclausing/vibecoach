import SwiftUI
import PhotosUI

/// De hoofd SwiftUI view die de chat interface toont.
struct ChatView: View {
    /// De viewmodel die de chat status en netwerklogica beheert.
    @StateObject var viewModel: ChatViewModel = ChatViewModel()

    /// Huidige item geselecteerd vanuit de iOS Photos library.
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Lijst met chatberichten
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            // Laadindicator
                            if viewModel.isTyping {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("Coach is aan het typen...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding()
                                .id("typingIndicator")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isTyping) { _, isTyping in
                        if isTyping {
                            withAnimation {
                                proxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                    }
                }

                // Geselecteerde afbeelding preview (indien aanwezig)
                if let image = viewModel.selectedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            viewModel.clearImage()
                            selectedItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Divider()

                // Onderste invoerbalk voor tekst en foto's
                HStack(alignment: .bottom, spacing: 12) {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                viewModel.selectedImage = uiImage
                            }
                        }
                    }

                    TextField("Bericht...", text: $viewModel.inputText, axis: .vertical)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .lineLimit(1...5)

                    Button(action: {
                        viewModel.sendMessage()
                        selectedItem = nil
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(viewModel.inputText.isEmpty && viewModel.selectedImage == nil ? .gray : .blue)
                    }
                    .disabled(viewModel.inputText.isEmpty && viewModel.selectedImage == nil)
                }
                .padding()
            }
            .navigationTitle("AI Fitness Coach")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Een herbruikbare view component die een enkel chatbericht tekent.
struct MessageBubble: View {
    /// Het bericht dat getoond moet worden.
    let message: ChatMessage

    /// Bepaalt of de afzender de gebruiker is (rechts uitgelijnd en blauw).
    var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if let imageData = message.attachedImageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(8)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(12)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isUser ? .white : .primary)
                        .cornerRadius(16)
                }
            }

            if !isUser { Spacer() }
        }
    }
}

#Preview {
    ChatView()
}
