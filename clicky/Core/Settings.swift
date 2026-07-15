import Foundation
import Combine

/// A modifier key that can be used as a push-to-talk trigger.
enum TriggerKey: String, CaseIterable, Identifiable, Codable {
    case option
    case control
    case command
    case function

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        case .command: return "Command ⌘"
        case .function: return "Globe/fn"
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        case .function: return "fn"
        }
    }
}

/// Persisted user preferences, backed by `UserDefaults`. API keys live in the
/// Keychain, not here.
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var dictateTrigger: TriggerKey {
        didSet { defaults.set(dictateTrigger.rawValue, forKey: Keys.dictateTrigger) }
    }
    @Published var agentTrigger: TriggerKey {
        didSet { defaults.set(agentTrigger.rawValue, forKey: Keys.agentTrigger) }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    @Published var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: Keys.locale) }
    }
    @Published var includeScreenshot: Bool {
        didSet { defaults.set(includeScreenshot, forKey: Keys.includeScreenshot) }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }
    @Published var showOnboarding: Bool {
        didSet { defaults.set(showOnboarding, forKey: Keys.showOnboarding) }
    }

    /// OpenAI API key, stored in the Keychain.
    var apiKey: String {
        get { Keychain.shared.string(for: Keys.apiKey) ?? "" }
        set {
            if newValue.isEmpty {
                Keychain.shared.delete(Keys.apiKey)
            } else {
                Keychain.shared.set(newValue, for: Keys.apiKey)
            }
            objectWillChange.send()
        }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    init() {
        dictateTrigger = TriggerKey(rawValue: defaults.string(forKey: Keys.dictateTrigger) ?? "") ?? .function
        agentTrigger = TriggerKey(rawValue: defaults.string(forKey: Keys.agentTrigger) ?? "") ?? .option
        model = defaults.string(forKey: Keys.model) ?? "gpt-4o"
        localeIdentifier = defaults.string(forKey: Keys.locale) ?? "en-US"
        includeScreenshot = defaults.object(forKey: Keys.includeScreenshot) as? Bool ?? true
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        showOnboarding = defaults.object(forKey: Keys.showOnboarding) as? Bool ?? true
    }

    private enum Keys {
        static let dictateTrigger = "dictateTrigger"
        static let agentTrigger = "agentTrigger"
        static let model = "model"
        static let locale = "localeIdentifier"
        static let includeScreenshot = "includeScreenshot"
        static let playSounds = "playSounds"
        static let showOnboarding = "showOnboarding"
        static let apiKey = "openai.apiKey"
    }
}
