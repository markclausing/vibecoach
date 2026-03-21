import SwiftUI
import PhotosUI
import SwiftData

/// De hoofd SwiftUI view die de chat interface toont.
struct ChatView: View {
    /// De viewmodel die de chat status en netwerklogica beheert.
    @StateObject var viewModel: ChatViewModel = ChatViewModel()

    /// Huidige item geselecteerd vanuit de iOS Photos library.
    @State private var selectedItem: PhotosPickerItem? = nil

    /// De globale app status om notificatie-tap acties af te vangen.
    @EnvironmentObject var appState: AppNavigationState

    /// SwiftData Context voor het berekenen van het atletisch profiel.
    @Environment(\.modelContext) private var modelContext
    @State private var currentProfile: AthleticProfile? = nil

    private let profileManager = AthleticProfileManager()

    /// Werkt het actuele profiel bij vanuit SwiftData.
    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            print("Kon profiel niet laden in ChatView: \(error)")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // SPRINT 6.3 - Proactieve Waarschuwing UI
                if currentProfile?.isRecoveryNeeded == true {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Let op: Je trainingsvolume is erg hoog. Neem voldoende rust.")
                            .font(.subheadline)
                            .bold()
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.8))
                    .foregroundColor(.white)
                }

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

                // Acties / Quick Replies
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button(action: {
                            refreshProfileContext()
                            viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile)
                        }) {
                            HStack {
                                if viewModel.isFetchingWorkout {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "figure.run")
                                }
                                Text("Analyseer laatste training")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemBlue).opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(20)
                        }
                        .disabled(viewModel.isFetchingWorkout)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
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
                        refreshProfileContext()
                        viewModel.sendMessage(contextProfile: currentProfile)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
            .onChange(of: appState.targetActivityId) { oldValue, newValue in
                if let activityId = newValue {
                    // Start de analyse en clear daarna de target uit de state zodat
                    // hij later opnieuw getriggerd kan worden indien nodig
                    refreshProfileContext()
                    viewModel.analyzeWorkout(withId: activityId, contextProfile: currentProfile)

                    Task { @MainActor in
                        appState.targetActivityId = nil
                    }
                }
            }
            .onAppear {
                refreshProfileContext()
            }
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
        .environmentObject(AppNavigationState())
}
