//
//  DevToolsManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine

@MainActor
final class DevToolsManager: ObservableObject {
    static let shared = DevToolsManager()

    enum Category: String, CaseIterable, Identifiable {
        case dev = "Dev"
        case security = "Security"

        var id: Self { self }

        var tools: [Tool] {
            Tool.allCases.filter { $0.category == self }
        }
    }

    enum Tool: String, CaseIterable, Identifiable {
        case json = "JSON"
        case base64 = "Base64"
        case url = "URL"
        case uuid = "UUID"
        case timestamp = "Time"
        case color = "Color"
        case link = "Link"
        case password = "Password"
        case jwt = "JWT"
        case hash = "Hash"
        case hex = "Hex"
        case html = "HTML"
        case unicode = "Unicode"
        case smart = "Smart"
        case regex = "Regex"
        case diff = "Diff"
        case cidr = "CIDR"

        var id: Self { self }

        var category: Category {
            switch self {
            case .json, .base64, .url, .uuid, .timestamp, .color, .link, .password: return .dev
            case .jwt, .hash, .hex, .html, .unicode, .smart, .regex, .diff, .cidr: return .security
            }
        }

        /// Tools that work on text the user types or pastes
        var takesInput: Bool {
            switch self {
            // Diff takes two texts through its own Paste A / Paste B buttons
            case .uuid, .color, .diff, .password: return false
            default: return true
            }
        }
    }

    @Published var tool: Tool = .json {
        didSet {
            guard tool != oldValue else { return }
            clearOutput()
            // A fresh password is the point of opening the tool
            if tool == .password { generatePassword() }
        }
    }

    var category: Category {
        get { tool.category }
        set {
            guard newValue != tool.category, let first = newValue.tools.first else { return }
            tool = first
        }
    }
    @Published var input: String = ""
    /// The regex pattern, or the second text of a diff
    @Published var secondaryInput: String = ""
    @Published var uppercaseUUID = false
    @Published var passwordOptions = PasswordOptions()
    @Published var passphraseMode = false
    @Published var passphraseWords = 5
    @Published private(set) var result: DevToolResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCopy = false

    private var copiedResetTask: Task<Void, Never>?

    private init() {}

    func run(_ transform: (String) throws -> DevToolResult) {
        do {
            show(try transform(input))
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    func show(_ result: DevToolResult) {
        self.result = result
        errorMessage = nil
        didCopy = false
    }

    func clearOutput() {
        result = nil
        errorMessage = nil
        didCopy = false
    }

    func pasteFromClipboard() {
        input = NSPasteboard.general.string(forType: .string) ?? ""
        clearOutput()
    }

    /// Fills the input with the clipboard and, when the text is recognized, picks the matching tool and runs it
    func loadFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        load(text, kind: ClipboardDetector.detect(text))
    }

    func load(_ text: String, kind: ClipboardKind?) {
        input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .jwt:
            tool = .jwt
            run { try SecurityTransforms.decodeJWT($0) }
        case .json:
            tool = .json
            run(DevTransforms.formatJSON)
        case .timestamp:
            tool = .timestamp
            run { try DevTransforms.convertTimestamp($0) }
        case .encoded:
            tool = .smart
            run(SecurityTransforms.smartDecode)
        case .link:
            tool = .link
            // Opening the notch on the "Shorten" hint is the request to shorten it
            Task { await ShortLinkManager.shared.shorten(input) }
        case .translate, nil:
            clearOutput()
        }
    }

    func pasteSecondaryFromClipboard() {
        secondaryInput = NSPasteboard.general.string(forType: .string) ?? ""
        clearOutput()
    }

    func useCurrentTime() {
        input = String(Int64(Date().timeIntervalSince1970))
        run { try DevTransforms.convertTimestamp($0) }
    }

    func copyResult() {
        guard let primary = result?.primary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primary, forType: .string)
        ClipboardWatcher.shared.ignoreCurrentChange()
        didCopy = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    // MARK: - Passwords

    /// Common lowercase words from the dictionary macOS ships, about 75,000 of them
    private lazy var passphraseList: [String] = {
        let text = (try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)) ?? ""
        let list = PasswordGenerator.wordList(from: text)
        return list.count >= 1000 ? list : Self.fallbackWords
    }()

    /// Used if the system dictionary can't be read; small, so passphrases get more words' worth of warning in the strength
    private static let fallbackWords = """
        able acid aged also area army away baby back ball band bank base bath bear beat been beer bell belt best bill bird blow blue boat body bomb bond bone book boom born boss both bowl bulk burn bush busy cake call calm came camp card care case cash cast cell chat chip city club coal coat code cold come cook cool cope copy core cost crew crop dark data date dawn days dead deal dean dear debt deep deny desk dial diet disc disk does done door dose down draw drew drop drug dual duke dust duty each earn ease east easy edge else even ever evil exit face fact fail fair fall farm fast fate fear feed feel feet fell felt file fill film find fine fire firm fish five flat flow food foot ford form fort four free from fuel full fund gain game gate gave gear gene gift girl give glad goal goes gold golf gone good gray grew grey grow gulf hair half hall hand hang hard harm hate have head hear heat held hell help here hero high hill hire hold hole holy home hope host hour huge hung hunt hurt idea inch into iron item jack jane jean john join jump jury just keen keep kent kept kick kill kind king knee knew know lack lady laid lake land lane last late lead left less life lift like line link list live load loan lock logo long look lord lose loss lost love luck made mail main make male many mark mass matt meal mean meat meet menu mere mike mile milk mill mind mine miss mode mood moon more most move much must name navy near neck need news next nice nick nine none nose note okay once only onto open oral over pace pack page paid pain pair palm park part pass past path peak pick pink pipe plan play plot plug plus poll pool poor port post pull pure push race rail rain rank rare rate read real rear rely rent rest rice rich ride ring rise risk road rock role roll roof room root rose rule rush safe said sake sale salt same sand save seat seed seek seem seen self sell send sent ship shop shot show shut sick side sign site size skin slip slow snow soft soil sold sole some song soon sort soul spot star stay step stop such suit sure take tale talk tall tank tape task team tech tell tend term test text than that them then they thin this thus till time tiny told tone took tool tour town tree trip true tune turn twin type unit upon used user vary vast very vice view vote wage wait wake walk wall want ward warm wash wave ways weak wear week well went were west what when whom wide wife wild will wind wine wing wire wise wish with wood word wore work yard yeah year your zero zone
        """.split(separator: " ").map(String.init)

    func generatePassword() {
        var rng = SystemRandomNumberGenerator()
        let text: String
        let bits: Double
        if passphraseMode {
            text = PasswordGenerator.passphrase(words: passphraseList, count: passphraseWords, separator: "-",
                                                capitalize: true, addNumber: true, using: &rng)
            bits = PasswordGenerator.passphraseEntropy(listSize: passphraseList.count, count: passphraseWords, addNumber: true)
        } else {
            text = PasswordGenerator.password(passwordOptions, using: &rng)
            bits = PasswordGenerator.entropy(passwordOptions)
        }
        guard !text.isEmpty else {
            result = nil
            errorMessage = "Pick at least one kind of character."
            return
        }
        let strength = PasswordGenerator.strength(bits: bits)
        show(DevToolResult(primary: text, detail: "\(strength.label) · \(Int(bits)) bits of entropy"))
    }

    /// Shows the system magnifier and reports the color under the cursor
    func pickColorFromScreen() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            Task { @MainActor in
                self?.show(DevTransforms.color(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                ))
            }
        }
    }
}
