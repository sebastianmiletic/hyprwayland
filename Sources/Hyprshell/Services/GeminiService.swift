import Foundation
import Security

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String
    let text: String
}

final class GeminiService: ObservableObject {
    @Published var messages: [ChatMessage] = [ChatMessage(role: "model", text: "Hi. I’m ready when you are.")]
    @Published var draft = ""
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published private(set) var hasAPIKey = false
    @Published var apiKeyDraft = ""

    private let keychain = GeminiKeychain()

    init() { hasAPIKey = keychain.read() != nil }

    func saveAPIKey() {
        let value = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        hasAPIKey = keychain.write(value)
        apiKeyDraft = ""
        errorMessage = hasAPIKey ? "" : "Could not save the key in Keychain."
    }

    func removeAPIKey() {
        keychain.remove(); hasAPIKey = false; apiKeyDraft = ""
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isLoading else { return }
        guard let apiKey = keychain.read() else { errorMessage = "Add a Gemini API key first."; return }
        messages.append(ChatMessage(role: "user", text: prompt)); draft = ""; isLoading = true; errorMessage = ""
        let history = messages.map { ["role": $0.role, "parts": [["text": $0.text]]] as [String: Any] }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { isLoading = false; return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["contents": history, "generationConfig": ["temperature": 0.7, "maxOutputTokens": 2048]])
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }; self.isLoading = false
                if let error { self.errorMessage = error.localizedDescription; return }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.compactMap({ $0["text"] as? String }).joined().nilIfEmpty else {
                    self.errorMessage = "Gemini did not return a response. Check the key and quota."; return
                }
                self.messages.append(ChatMessage(role: "model", text: text))
            }
        }.resume()
    }
}

private final class GeminiKeychain {
    private let service = "com.sebastianmiletic.hyprshell.gemini"
    private let account = "default"
    func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    @discardableResult func write(_ value: String) -> Bool {
        remove()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    func remove() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
