//
//  DevToolsView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

struct DevToolsView: View {
    @ObservedObject var tools = DevToolsManager.shared
    @ObservedObject var links = ShortLinkManager.shared
    @Default(.shortLinkService) var linkService
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolPicker
            controls
            output
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .acceptsNotchKeyboardInput()
    }

    // MARK: - Tool picker

    private var toolPicker: some View {
        HStack(spacing: 6) {
            CapsuleSegmentedPicker(options: DevToolsManager.Category.allCases, selection: $tools.category, title: \.rawValue)

            // Tight spacing so all nine Security tools fit next to the switch
            HStack(spacing: 4) {
                ForEach(tools.category.tools) { tool in
                    toolChip(tool)
                }
            }
        }
    }

    private func toolChip(_ tool: DevToolsManager.Tool) -> some View {
        Button {
            withAnimation(.smooth) { tools.tool = tool }
        } label: {
            Text(tool.rawValue)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        tools.tool == tool
                            ? Color.effectiveAccent.opacity(0.35)
                            : Color(nsColor: .secondarySystemFill)
                    )
                )
                .foregroundStyle(tools.tool == tool ? .white : .gray)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Input and actions

    private var controls: some View {
        HStack(spacing: 6) {
            if tools.tool == .regex {
                TextField("Pattern", text: $tools.secondaryInput)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .onSubmit(runPrimaryAction)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                    .frame(width: 150)
            }
            if tools.tool.takesInput {
                inputField
                actionButton("Paste", icon: "doc.on.clipboard") {
                    tools.pasteFromClipboard()
                }
            }

            switch tools.tool {
            case .json:
                actionButton("Format", primary: true) { tools.run(DevTransforms.formatJSON) }
                actionButton("Minify") { tools.run(DevTransforms.minifyJSON) }
            case .base64:
                actionButton("Encode", primary: true) { tools.run { DevTransforms.base64Encode($0) } }
                actionButton("Decode") { tools.run(DevTransforms.base64Decode) }
            case .url:
                actionButton("Encode", primary: true) { tools.run { DevTransforms.urlEncode($0) } }
                actionButton("Encode ×2") {
                    tools.run { DevTransforms.urlEncode(DevTransforms.urlEncode($0).primary) }
                }
                actionButton("Decode") { tools.run(DevTransforms.urlDecode) }
            case .jwt:
                actionButton("Decode", primary: true) { tools.run { try SecurityTransforms.decodeJWT($0) } }
            case .hash:
                ForEach(SecurityTransforms.HashAlgorithm.allCases) { algorithm in
                    actionButton(LocalizedStringKey(algorithm.rawValue), primary: algorithm == .sha256) {
                        tools.run { SecurityTransforms.hash($0, algorithm) }
                    }
                }
            case .hex:
                actionButton("Encode", primary: true) { tools.run { SecurityTransforms.hexEncode($0) } }
                actionButton("Decode") { tools.run(SecurityTransforms.hexDecode) }
            case .html:
                actionButton("Encode", primary: true) { tools.run { SecurityTransforms.htmlEncode($0) } }
                actionButton("Decode") { tools.run { SecurityTransforms.htmlDecode($0) } }
            case .unicode:
                actionButton("Escape", primary: true) { tools.run { SecurityTransforms.unicodeEscape($0) } }
                actionButton("Unescape") { tools.run(SecurityTransforms.unicodeUnescape) }
            case .smart:
                actionButton("Decode all layers", primary: true) { tools.run(SecurityTransforms.smartDecode) }
            case .regex:
                actionButton("Test", primary: true) { runPrimaryAction() }
            case .diff:
                actionButton("Paste A", icon: "doc.on.clipboard") { tools.pasteFromClipboard() }
                Text(lineCountLabel(tools.input))
                    .font(.caption)
                    .foregroundStyle(.gray)
                actionButton("Paste B", icon: "doc.on.clipboard") { tools.pasteSecondaryFromClipboard() }
                Text(lineCountLabel(tools.secondaryInput))
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                actionButton("Compare", primary: true) { runPrimaryAction() }
            case .cidr:
                actionButton("Analyze", primary: true) { tools.run(SecurityTransforms.cidr) }
            case .timestamp:
                actionButton("Convert", primary: true) { tools.run { try DevTransforms.convertTimestamp($0) } }
                actionButton("Now") { tools.useCurrentTime() }
            case .uuid:
                actionButton("Generate", icon: "arrow.triangle.2.circlepath", primary: true) {
                    tools.show(DevTransforms.uuid(uppercase: tools.uppercaseUUID))
                }
                Toggle("Uppercase", isOn: $tools.uppercaseUUID)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
            case .color:
                actionButton("Pick color from screen", icon: "eyedropper", primary: true) {
                    tools.pickColorFromScreen()
                }
                Spacer()
            case .password:
                passwordControls
            case .link:
                CapsuleSegmentedPicker(options: ShortLinkService.allCases, selection: $linkService, title: \.rawValue)
                    .fixedSize()
                actionButton(links.isWorking ? "Shortening…" : "Shorten", icon: "link", primary: true) { runPrimaryAction() }
                    .disabled(links.isWorking)
            }
        }
    }

    private var passwordControls: some View {
        HStack(spacing: 6) {
            CapsuleSegmentedPicker(options: [false, true], selection: $tools.passphraseMode) { $0 ? "Passphrase" : "Password" }
                .fixedSize()
            HStack(spacing: 3) {
                stepButton("minus") { adjustLength(-1) }
                Text(tools.passphraseMode ? "\(tools.passphraseWords) words" : "\(tools.passwordOptions.length) chars")
                    .font(.system(.caption, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 54)
                stepButton("plus") { adjustLength(1) }
            }
            if !tools.passphraseMode {
                optionChip("A–Z", isOn: $tools.passwordOptions.uppercase)
                optionChip("a–z", isOn: $tools.passwordOptions.lowercase)
                optionChip("0–9", isOn: $tools.passwordOptions.digits)
                optionChip("#$%", isOn: $tools.passwordOptions.symbols)
                optionChip("Easy to read", isOn: $tools.passwordOptions.avoidAmbiguous)
                    .help("Leaves out look-alikes such as 0/O and 1/l/I")
            }
            Spacer(minLength: 0)
            actionButton("New", icon: "arrow.triangle.2.circlepath", primary: true) { tools.generatePassword() }
        }
        .onChange(of: tools.passwordOptions) { tools.generatePassword() }
        .onChange(of: tools.passphraseMode) { tools.generatePassword() }
    }

    private func adjustLength(_ step: Int) {
        if tools.passphraseMode {
            let range = PasswordGenerator.wordCountRange
            tools.passphraseWords = min(max(tools.passphraseWords + step, range.lowerBound), range.upperBound)
            tools.generatePassword()
        } else {
            let range = PasswordGenerator.lengthRange
            // Steps of 4 past 16, where single characters matter less
            let size = tools.passwordOptions.length >= 16 ? 4 : 1
            tools.passwordOptions.length = min(max(tools.passwordOptions.length + step * size, range.lowerBound), range.upperBound)
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(nsColor: .secondarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func optionChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn.wrappedValue ? Color.effectiveAccent.opacity(0.35) : Color(nsColor: .secondarySystemFill)))
                .foregroundStyle(isOn.wrappedValue ? .white : .gray)
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize()
    }

    private var inputField: some View {
        TextField(placeholder, text: $tools.input)
            .textFieldStyle(.plain)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .focused($isInputFocused)
            .onSubmit(runPrimaryAction)
            .onExitCommand {
                isInputFocused = false
                NotchKeyboardFocus.returnKeyboard()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
    }

    private var placeholder: LocalizedStringKey {
        switch tools.tool {
        case .json: return "Paste JSON"
        case .base64: return "Text or Base64"
        case .url: return "Text or encoded URL"
        case .timestamp: return "1761523611 or 2025-10-27 07:06:51"
        case .jwt: return "eyJhbGciOi... (Bearer prefix is fine)"
        case .hash: return "Text to hash"
        case .hex: return "Text or 68656c6c6f"
        case .html: return "Text or &lt;b&gt;"
        case .unicode: return "Text or \\u0041"
        case .smart: return "Encoded payload, any mix of layers"
        case .regex: return "Text to search"
        case .cidr: return "192.168.1.0/24 or an IP"
        case .link: return "https://… a long link to shorten"
        case .uuid, .color, .diff, .password: return ""
        }
    }

    private func lineCountLabel(_ text: String) -> String {
        guard !text.isEmpty else { return "empty" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return lines == 1 ? "1 line" : "\(lines) lines"
    }

    /// Return in the input field runs the first action of the tool
    private func runPrimaryAction() {
        switch tools.tool {
        case .json: tools.run(DevTransforms.formatJSON)
        case .base64: tools.run { DevTransforms.base64Encode($0) }
        case .url: tools.run { DevTransforms.urlEncode($0) }
        case .timestamp: tools.run { try DevTransforms.convertTimestamp($0) }
        case .jwt: tools.run { try SecurityTransforms.decodeJWT($0) }
        case .hash: tools.run { SecurityTransforms.hash($0, .sha256) }
        case .hex: tools.run { SecurityTransforms.hexEncode($0) }
        case .html: tools.run { SecurityTransforms.htmlEncode($0) }
        case .unicode: tools.run { SecurityTransforms.unicodeEscape($0) }
        case .smart: tools.run(SecurityTransforms.smartDecode)
        case .regex: tools.run { [pattern = tools.secondaryInput] in try SecurityTransforms.regexMatches(pattern: pattern, in: $0) }
        case .diff: tools.show(SecurityTransforms.lineDiff(tools.input, tools.secondaryInput))
        case .cidr: tools.run(SecurityTransforms.cidr)
        case .link:
            let text = tools.input
            Task { await links.shorten(text, service: linkService) }
        case .password: tools.generatePassword()
        case .uuid, .color: break
        }
    }

    private func actionButton(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.system(.caption, design: .rounded, weight: primary ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(primary ? Color.effectiveAccent : Color(nsColor: .secondarySystemFill)))
            .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize()
    }

    // MARK: - Output

    @ViewBuilder
    private var output: some View {
        if tools.tool == .link {
            ShortLinkPanel()
        } else {
            standardOutput
        }
    }

    private var standardOutput: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let error = tools.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if let result = tools.result {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if tools.tool == .color, let color = Color(hex: result.primary) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color)
                                        .frame(width: 14, height: 14)
                                }
                                Text(result.primary)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            if let detail = result.detail {
                                Text(detail)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.gray)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .allowsScrollingInOpenNotch()
                } else {
                    Text("Result appears here")
                        .font(.callout)
                        .foregroundStyle(.gray.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if tools.result != nil {
                actionButton(tools.didCopy ? "Copied" : "Copy", icon: tools.didCopy ? "checkmark" : "doc.on.doc") {
                    tools.copyResult()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

/// Shown on the closed notch for a few seconds after copying something Dev Tools can decode.
/// Opening the notch while it shows loads the text into Dev Tools.
struct ClipboardSuggestionLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let kind: ClipboardKind

    private var label: LocalizedStringKey {
        switch kind {
        case .jwt: return "JWT"
        case .json: return "JSON"
        case .timestamp: return "Time"
        case .encoded: return "Decode"
        case .link: return "Shorten"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        }
    }

    var body: some View {
        let sideWidth = FocusLiveActivity.sideWidth(notchHeight: vm.effectiveClosedNotchHeight)

        HStack {
            Image(systemName: kind == .link ? "link" : kind == .translate ? "character.bubble" : kind == .summarize ? "sparkles" : "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help(kind == .link ? "Copied a long link. Open the notch to shorten it."
              : kind == .translate ? "Copied text in another language. Open the notch to translate it."
              : "Copied text Dev Tools can decode. Open the notch to see it.")
    }
}

private extension Color {
    /// Parses "#RRGGBB"
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview {
    DevToolsView()
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 150)
        .background(.black)
}
