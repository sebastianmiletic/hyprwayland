import AppKit
import Foundation
import Security
import LocalAuthentication

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: String
    let text: String
    let model: String?
    init(id: UUID = UUID(), role: String, text: String, model: String? = nil) { self.id = id; self.role = role; self.text = text; self.model = model }
}

struct GeminiScreenAnswer {
    let text: String
    let isMultipleChoice: Bool
}

struct GeminiModelUsage: Identifiable {
    let id: String
    let name: String
    let used: Int
    let quota: Int
    var remaining: Int { max(0, quota - used) }
}

private struct GeminiModel {
    let id: String
    let name: String
    let quota: Int
}

/// Native implementation of the source configuration's text model router.
/// Requests move through the configured models in order and locally reserve the
/// same daily quotas (reset at midnight in America/Los_Angeles).
final class GeminiService: ObservableObject {
    @Published var messages: [ChatMessage] = [ChatMessage(role: "model", text: "Hi. I’m ready when you are.")]
    @Published var draft = ""
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published private(set) var hasAPIKey = false
    @Published var apiKeyDraft = ""
    @Published private(set) var currentModelID = ""
    @Published private(set) var modelUsages: [GeminiModelUsage] = []
    @Published private(set) var inputTokens = 0
    @Published private(set) var outputTokens = 0

    private let keychain = GeminiKeychain()
    private let models = [
        GeminiModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", quota: 500),
        GeminiModel(id: "gemini-2.5-flash-lite", name: "Gemini 2.5 Flash Lite", quota: 1_000),
        GeminiModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", quota: 1_000)
    ]
    private var usageCounts: [String: Int] = [:]
    private var usageDate = ""
    private let usageURL: URL
    private let historyURL: URL
    private var requestTask: URLSessionDataTask?
    private var screenRequestTask: URLSessionDataTask?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ryft", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        usageURL = support.appendingPathComponent("ai-model-usage.json")
        historyURL = support.appendingPathComponent("ai-conversation.json")
        hasAPIKey = keychain.read() != nil
        loadUsage()
        loadHistory()
    }

    var currentModelName: String { models.first(where: { $0.id == currentModelID })?.name ?? "Automatic" }

    func refreshCredentialState() { hasAPIKey = keychain.read() != nil }

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

    func newConversation() {
        requestTask?.cancel(); requestTask = nil; isLoading = false; errorMessage = ""
        messages = [ChatMessage(role: "model", text: "Hi. I’m ready when you are.")]
        saveHistory()
    }

    func stop() {
        requestTask?.cancel(); requestTask = nil; isLoading = false
    }

    func copyLastResponse() {
        guard let text = messages.last(where: { $0.role == "model" })?.text else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

    func openAIStudio() {
        if let url = URL(string: "https://aistudio.google.com/app/apikey") { NSWorkspace.shared.open(url) }
    }

    func answerScreen(imageData: Data, completion: @escaping (Result<GeminiScreenAnswer, Error>) -> Void) {
        guard let apiKey = keychain.read() else {
            hasAPIKey = false
            completion(.failure(NSError(domain: "Ryft.Gemini", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add a Gemini API key in the Assistant settings first."])))
            return
        }
        hasAPIKey = true
        screenRequestTask?.cancel()
        resetUsageIfNeeded()
        guard let first = models.firstIndex(where: { usageCounts[$0.id, default: 0] < $0.quota }) else {
            completion(.failure(NSError(domain: "Ryft.Gemini", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Gemini model quota is currently available."])))
            return
        }
        requestScreen(imageData: imageData, apiKey: apiKey, modelIndex: first, completion: completion)
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isLoading else { return }
        guard let apiKey = keychain.read() else { hasAPIKey = false; errorMessage = "Add a Gemini API key first."; return }
        hasAPIKey = true; messages.append(ChatMessage(role: "user", text: prompt)); saveHistory(); draft = ""; isLoading = true; errorMessage = ""
        resetUsageIfNeeded()
        guard let first = models.firstIndex(where: { usageCounts[$0.id, default: 0] < $0.quota }) else {
            isLoading = false; errorMessage = "No AI model quota is currently available."; return
        }
        request(apiKey: apiKey, modelIndex: first)
    }

    private func request(apiKey: String, modelIndex: Int) {
        guard modelIndex < models.count else { isLoading = false; errorMessage = "No AI model quota is currently available."; return }
        let model = models[modelIndex]
        if usageCounts[model.id, default: 0] >= model.quota { request(apiKey: apiKey, modelIndex: modelIndex + 1); return }
        reserve(model); currentModelID = model.id
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.id):generateContent") else { failover(apiKey: apiKey, failed: model, next: modelIndex + 1); return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let history = messages.dropFirst().map { ["role": $0.role == "model" ? "model" : "user", "parts": [["text": $0.text]]] as [String: Any] }
        let payload: [String: Any] = [
            "contents": Array(history),
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "generationConfig": ["temperature": 0.5]
        ]
        do { request.httpBody = try JSONSerialization.data(withJSONObject: payload) }
        catch { isLoading = false; errorMessage = error.localizedDescription; return }
        requestTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestTask = nil
                if let urlError = error as? URLError, urlError.code == .cancelled { self.isLoading = false; return }
                if let error { self.isLoading = false; self.errorMessage = error.localizedDescription; return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if status == 401 || status == 403 {
                    self.isLoading = false; self.errorMessage = self.apiError(json) ?? "The Gemini API key was rejected."; return
                }
                if status == 404 || status == 429 || !(200..<300).contains(status) {
                    self.failover(apiKey: apiKey, failed: model, next: modelIndex + 1, finalMessage: self.apiError(json)); return
                }
                guard let candidates = json?["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.compactMap({ $0["text"] as? String }).joined().nilIfEmpty else {
                    self.failover(apiKey: apiKey, failed: model, next: modelIndex + 1, finalMessage: self.apiError(json)); return
                }
                if let usage = json?["usageMetadata"] as? [String: Any] {
                    self.inputTokens = usage["promptTokenCount"] as? Int ?? 0
                    self.outputTokens = usage["candidatesTokenCount"] as? Int ?? 0
                }
                self.messages.append(ChatMessage(role: "model", text: self.humanize(text), model: model.id)); self.isLoading = false; self.errorMessage = ""; self.saveHistory()
            }
        }
        requestTask?.resume()
    }

    private func requestScreen(imageData: Data, apiKey: String, modelIndex: Int, completion: @escaping (Result<GeminiScreenAnswer, Error>) -> Void) {
        guard modelIndex < models.count else {
            completion(.failure(NSError(domain: "Ryft.Gemini", code: 3, userInfo: [NSLocalizedDescriptionKey: "Gemini could not answer from the current screen."])))
            return
        }
        let model = models[modelIndex]
        if usageCounts[model.id, default: 0] >= model.quota {
            requestScreen(imageData: imageData, apiKey: apiKey, modelIndex: modelIndex + 1, completion: completion)
            return
        }
        reserve(model); currentModelID = model.id
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.id):generateContent") else {
            completion(.failure(NSError(domain: "Ryft.Gemini", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create the Gemini request."])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let prompt = """
        Inspect this screenshot and identify the primary question currently visible to the user. Solve it using only what is visible and your general knowledge.
        If it is multiple choice, reply exactly as CHOICE: followed by one letter from A through E.
        Otherwise reply as ANSWER: followed by one concise answer of at most 16 words.
        If there is no readable question, reply exactly ANSWER: No question found.
        Do not include reasoning, Markdown, or any other text.
        """
        let payload: [String: Any] = [
            "contents": [["role": "user", "parts": [
                ["text": prompt],
                ["inline_data": ["mime_type": "image/jpeg", "data": imageData.base64EncodedString()]]
            ]]],
            "generationConfig": ["temperature": 0.1, "maxOutputTokens": 80]
        ]
        do { request.httpBody = try JSONSerialization.data(withJSONObject: payload) }
        catch { completion(.failure(error)); return }
        screenRequestTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.screenRequestTask = nil
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                if let error { completion(.failure(error)); return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if status == 401 || status == 403 {
                    completion(.failure(NSError(domain: "Ryft.Gemini", code: status, userInfo: [NSLocalizedDescriptionKey: self.apiError(json) ?? "The Gemini API key was rejected."])))
                    return
                }
                guard (200..<300).contains(status),
                      let candidates = json?["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let raw = parts.compactMap({ $0["text"] as? String }).joined().nilIfEmpty else {
                    self.usageCounts[model.id] = model.quota; self.saveUsage()
                    if modelIndex + 1 < self.models.count {
                        self.requestScreen(imageData: imageData, apiKey: apiKey, modelIndex: modelIndex + 1, completion: completion)
                    } else {
                        completion(.failure(NSError(domain: "Ryft.Gemini", code: status, userInfo: [NSLocalizedDescriptionKey: self.apiError(json) ?? "Gemini could not read the visible question."])))
                    }
                    return
                }
                completion(.success(self.parseScreenAnswer(raw)))
            }
        }
        screenRequestTask?.resume()
    }

    private func parseScreenAnswer(_ raw: String) -> GeminiScreenAnswer {
        let clean = humanize(raw).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.uppercased().hasPrefix("CHOICE:") {
            let value = clean.dropFirst("CHOICE:".count).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let letter = value.first.map(String.init) ?? "?"
            return GeminiScreenAnswer(text: letter, isMultipleChoice: true)
        }
        let answer = clean.uppercased().hasPrefix("ANSWER:") ? String(clean.dropFirst("ANSWER:".count)).trimmingCharacters(in: .whitespacesAndNewlines) : clean
        return GeminiScreenAnswer(text: String(answer.prefix(140)), isMultipleChoice: false)
    }

    private func failover(apiKey: String, failed: GeminiModel, next: Int, finalMessage: String? = nil) {
        usageCounts[failed.id] = failed.quota; saveUsage()
        if next < models.count { request(apiKey: apiKey, modelIndex: next) }
        else { isLoading = false; errorMessage = finalMessage ?? "No AI model quota is currently available." }
    }

    private func reserve(_ model: GeminiModel) { usageCounts[model.id, default: 0] += 1; saveUsage() }

    private func resetUsageIfNeeded() {
        let today = Self.today
        if usageDate != today { usageDate = today; usageCounts = [:]; saveUsage() }
    }

    private func loadUsage() {
        if let data = try? Data(contentsOf: usageURL), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["date"] as? String == Self.today {
            usageDate = Self.today; usageCounts = object["counts"] as? [String: Int] ?? [:]
        } else { usageDate = Self.today; usageCounts = [:] }
        publishUsage()
    }

    private func saveUsage() {
        let object: [String: Any] = ["date": usageDate, "counts": usageCounts]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: usageURL, options: .atomic) }
        publishUsage()
    }

    private func publishUsage() { modelUsages = models.map { GeminiModelUsage(id: $0.id, name: $0.name, used: usageCounts[$0.id, default: 0], quota: $0.quota) } }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode([ChatMessage].self, from: data), !saved.isEmpty else { return }
        messages = Array(saved.suffix(80))
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(Array(messages.suffix(80))) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func apiError(_ json: [String: Any]?) -> String? { (json?["error"] as? [String: Any])?["message"] as? String }
    private func humanize(_ text: String) -> String { text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: #"\\\(|\\\)|\\\[|\\\]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }

    private var systemPrompt: String {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let date = Date().formatted(date: .abbreviated, time: .shortened)
        return """
        ## Style
        - Use casual tone, don't be formal!
        - Always be brief and to the point, unless asked otherwise
        - Don't repeat the user's question
        - Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept

        ## Context (ignore when irrelevant)
        - You are a helpful and inspiring sidebar assistant on a macOS system
        - Desktop environment: macOS (Aqua)
        - Current date & time: \(date)
        - Focused app: \(app)

        ## Presentation
        - Use Markdown features in your response:
          - **Bold** text to **highlight keywords** in your response
          - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.
        - Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!
        - Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).

        Thanks!

        ## Non-negotiable output rules
        Write in clean, natural, human-readable language. Never use emojis, emoticons, kaomoji, or decorative pictographs. Never use dollar signs as LaTeX delimiters or terminal prompts. Write mathematics as ordinary text with readable Unicode symbols, and show commands without a leading prompt character.
        """
    }

    private static var today: String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "America/Los_Angeles"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: Date())
    }
}

private final class GeminiKeychain {
    private let service = "com.sebastianmiletic.ryft.gemini"
    // A new account avoids inheriting access-control lists from development
    // builds that could trigger a macOS login-password dialog. Users paste the
    // API key once; stable signed updates can then read it without interaction.
    private let account = "assistant-v2"
    func read() -> String? {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context, "u_AuthUI": "u_AuthUIF"]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    @discardableResult func write(_ value: String) -> Bool {
        let context = LAContext(); context.interactionNotAllowed = true
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecUseAuthenticationContext as String: context, "u_AuthUI": "u_AuthUIF"]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let updated = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var item = match
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    func remove() {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecUseAuthenticationContext as String: context, "u_AuthUI": "u_AuthUIF"]
        SecItemDelete(query as CFDictionary)
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
