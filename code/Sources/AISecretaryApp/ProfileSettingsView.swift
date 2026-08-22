import SwiftUI
import AppKit
import AssistantState
import LLMProvider
import SecretaryCore

struct ProfileSettingsView: View {
    @Environment(\.palette) private var theme

    let profiles: ProfileLibrary
    let profileID: UUID
    let appearance: Appearance
    let vendorStatus: VendorStatus
    let secretary: Secretary

    @State private var draft: Draft
    @State private var note: String?
    @State private var cliPathDraft: String

    init(
        profiles: ProfileLibrary,
        profileID: UUID,
        appearance: Appearance,
        vendorStatus: VendorStatus,
        secretary: Secretary
    ) {
        self.profiles = profiles
        self.profileID = profileID
        self.appearance = appearance
        self.vendorStatus = vendorStatus
        self.secretary = secretary
        _draft = State(initialValue: Draft(profiles.profile(profileID)))
        _cliPathDraft = State(initialValue: vendorStatus.cliPath)
    }

    private var subject: SecretaryProfile { profiles.profile(profileID) }

    var body: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Text("Profile")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: appearance.settings.panelSpacing, verticalSpacing: appearance.settings.panelSpacing) {
                nameField
                genderRow
                ageRow
                personalityField

                dividerRow
                pictureRow

                dividerRow
                vendorRow
                if vendorStatus.vendor.executableIsUserSupplied {
                    cliPathRow
                }
                modelRow
                if vendorStatus.vendor.supportsEffort {
                    effortRow
                }
            }

            HStack(spacing: appearance.settings.panelSpacing) {
                Button("Save") { save() }
                    .buttonStyle(.bordered)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .disabled(!draft.hasChanges(from: subject))
                if profiles.canDelete {
                    Button("Delete") { delete() }
                        .buttonStyle(.plain)
                        .font(.system(size: appearance.settings.footnoteFontSize))
                        .foregroundStyle(theme.mutedText.color)
                }
                Spacer()
            }

            if let note {
                Text(note)
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
        }
        .padding(appearance.settings.panelPadding)
        .background(PanelBoxGround(palette: theme, liquidGlass: appearance.settings.liquidGlass))
        .onChange(of: profiles.artworkRevision) { _, _ in note = nil }
    }

    private var nameField: some View {
        GridRow {
            fieldLabel("Name")
            TextField("Miku", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: appearance.settings.footnoteFontSize))
        }
    }

    private var genderRow: some View {
        GridRow {
            fieldLabel("Gender")
            HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing) {
            Menu {
                Button("Female") { draft.genderChoice = .female }
                Button("Male") { draft.genderChoice = .male }
                Button("Other…") { draft.genderChoice = .other }
            } label: {
                Text(draft.genderChoice.label)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if draft.genderChoice == .other {
                TextField("e.g. non-binary", text: $draft.genderText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: appearance.settings.footnoteFontSize))
            }
            Spacer(minLength: 0)
            }
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    private var ageRow: some View {
        GridRow {
            fieldLabel("Age")
            HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing) {
            Menu {
                Button("Child") { draft.ageChoice = .child }
                Button("Teenager") { draft.ageChoice = .teenager }
                Button("Adult") { draft.ageChoice = .adult }
                Button("Exact age…") { draft.ageChoice = .exact }
            } label: {
                Text(draft.ageChoice.label)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if draft.ageChoice == .exact {
                TextField("17", text: $draft.ageText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .frame(width: 44)
            }
            Spacer(minLength: 0)
            }
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    private var personalityField: some View {
        GridRow {
            fieldLabel("Personality")
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                TextField(SecretaryProfile.defaultPersonality, text: $draft.personality)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                Text("Free text — who she is, in your words. Blank means \(SecretaryProfile.defaultPersonality).")
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
        }
    }

    private var pictureRow: some View {
        let id = profileID
        let hasPicture = profiles.hasArtwork(for: id)

        return GridRow {
            fieldLabel("Picture")
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing) {
                Menu {
                    Button(hasPicture ? "Replace picture…" : "Choose picture…") {
                        choosePicture()
                    }
                    if hasPicture {
                        Button("Clear") { note = profiles.clearArtworkReportingProblem(for: id) }
                    }
                } label: {
                    HStack(spacing: appearance.settings.panelSpacing * 0.5) {
                        Image(systemName: hasPicture ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: appearance.settings.hintFontSize * 0.9))
                            .foregroundStyle(hasPicture ? theme.success.color : theme.mutedText.color)
                        Text(hasPicture ? "Chosen" : "None")
                            .font(.system(size: appearance.settings.hintFontSize + 1))
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .id("picture-\(profiles.artworkRevision)-\(id)")
                Spacer(minLength: 0)
                }
                Text("Shown in every state — the colour and badge say what she's doing.")
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
        }
    }

    private var vendorRow: some View {
        GridRow {
            fieldLabel("AI")
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing * 0.4) {
                    Menu(vendorStatus.vendor.displayName) {
                        ForEach(AIVendor.known) { candidate in
                            Button {
                                vendorStatus.choose(vendorID: candidate.id)
                            } label: {
                                Label(
                                    candidate.displayName,
                                    systemImage: candidate.id == vendorStatus.vendor.id ? "checkmark" : ""
                                )
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .fixedSize()
                    Button("Check") { vendorStatus.refresh() }
                        .buttonStyle(.plain)
                        .font(.system(size: appearance.settings.hintFontSize))
                        .foregroundStyle(theme.mutedText.color)
                    connectionMarker
                }
                if let message = vendorStatus.connection.message {
                    Text(message)
                        .font(.system(size: appearance.settings.hintFontSize))
                        .foregroundStyle(
                            vendorStatus.connection.isFailed
                                ? theme.danger.color
                                : theme.mutedText.color
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caution = vendorStatus.vendor.caution {
                    Label(caution, systemImage: "exclamationmark.triangle")
                        .font(.system(size: appearance.settings.hintFontSize))
                        .foregroundStyle(theme.warning.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { vendorStatus.refresh() }
    }

    private var cliPathRow: some View {
        GridRow {
            fieldLabel("CLI Path")
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing * 0.4) {
                    TextField("", text: $cliPathDraft, prompt: Text(OpenCodeLocator.knownPaths[0]))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: appearance.settings.footnoteFontSize))
                        .onSubmit { vendorStatus.choose(cliPath: cliPathDraft) }
                    Button("Test") { vendorStatus.choose(cliPath: cliPathDraft) }
                        .buttonStyle(.bordered)
                        .font(.system(size: appearance.settings.footnoteFontSize))
                }
                Text("Leave it empty and I'll look in the usual places. Test keeps what you typed and checks it.")
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: vendorStatus.cliPath) { _, path in cliPathDraft = path }
    }

    @ViewBuilder
    private var connectionMarker: some View {
        if vendorStatus.connection.isChecking {
            ProgressView()
                .controlSize(.small)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        } else if vendorStatus.connection.isConnected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.success.color)
                .font(.system(size: appearance.settings.hintFontSize))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        } else if vendorStatus.connection.isFailed {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(theme.danger.color)
                .font(.system(size: appearance.settings.hintFontSize))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        }
    }

    private var modelRow: some View {
        GridRow {
            fieldLabel("Model")
            settingControl(
                value: secretary.effectiveModelName,
                inherited: secretary.isModelInherited
            ) {
                Button {
                    secretary.chooseModel(nil)
                } label: {
                    Label(
                        "The tool's own default",
                        systemImage: secretary.isModelInherited ? "checkmark" : ""
                    )
                }
                Divider()
                ForEach(vendorStatus.models, id: \.id) { candidate in
                    Button {
                        secretary.chooseModel(candidate)
                    } label: {
                        Label(
                            candidate.displayName,
                            systemImage: secretary.chosenModel == candidate ? "checkmark" : ""
                        )
                    }
                }
            }
        }
    }

    private var effortRow: some View {
        GridRow {
            fieldLabel("Effort")
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                settingControl(
                    value: secretary.effectiveEffortName,
                    inherited: secretary.isEffortInherited
                ) {
                    Button {
                        secretary.chooseEffort(nil)
                    } label: {
                        Label(
                            "The tool's own default",
                            systemImage: secretary.isEffortInherited ? "checkmark" : ""
                        )
                    }
                    Divider()
                    ForEach(Effort.allCases, id: \.rawValue) { candidate in
                        Button {
                            secretary.chooseEffort(candidate)
                        } label: {
                            Label(
                                candidate.rawValue,
                                systemImage: secretary.chosenEffort == candidate ? "checkmark" : ""
                            )
                        }
                    }
                }
                Text("Change with /model <id> or /effort <level> in the chat. The dashed ring marks one the app didn't pick, which can move if you reconfigure the tool it runs on.")
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingControl<Choices: View>(
        value: String,
        inherited: Bool,
        @ViewBuilder choices: () -> Choices
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing * 0.5) {
            Menu(content: choices) {
                Text(value)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if inherited {
                Image(systemName: "circle.dashed")
                    .font(.system(size: appearance.settings.hintFontSize * 0.8))
                    .foregroundStyle(theme.mutedText.color)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: appearance.settings.footnoteFontSize))
            .foregroundStyle(theme.mutedText.color)
            .lineLimit(1)
            .fixedSize()
    }

    private var dividerRow: some View {
        GridRow {
            Divider().gridCellColumns(2)
        }
    }

    private func save() {
        profiles.update(draft.profile(id: profileID))
        note = nil
    }

    private func delete() {
        profiles.delete(profileID)
    }

    private func choosePicture() {
        guard let source = ImagePicker.promptForImage(
            message: "Choose a picture for \(subject.displayName)."
        ) else { return }

        guard let image = NSImage(contentsOf: source), let png = image.pngData else {
            note = "Couldn't read that image."
            return
        }
        note = profiles.setArtworkReportingProblem(pngData: png, for: profileID)
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct Draft {
    enum GenderChoice: Equatable {
        case female, male, other

        var label: String {
            switch self {
            case .female: return "Female"
            case .male: return "Male"
            case .other: return "Other"
            }
        }
    }

    enum AgeChoice: Equatable {
        case child, teenager, adult, exact

        var label: String {
            switch self {
            case .child: return "Child"
            case .teenager: return "Teenager"
            case .adult: return "Adult"
            case .exact: return "Exact"
            }
        }
    }

    var name: String
    var genderChoice: GenderChoice
    var genderText: String
    var ageChoice: AgeChoice
    var ageText: String
    var personality: String

    init(_ profile: SecretaryProfile) {
        name = profile.name
        switch profile.gender {
        case .female:
            genderChoice = .female
            genderText = ""
        case .male:
            genderChoice = .male
            genderText = ""
        case .other(let text):
            genderChoice = .other
            genderText = text
        }
        switch profile.age {
        case .child:
            ageChoice = .child
            ageText = ""
        case .teenager:
            ageChoice = .teenager
            ageText = ""
        case .adult:
            ageChoice = .adult
            ageText = ""
        case .years(let years):
            ageChoice = .exact
            ageText = "\(years)"
        }
        personality = profile.personality
    }

    func profile(id: UUID) -> SecretaryProfile {
        SecretaryProfile(id: id, name: name, age: age, gender: gender, personality: personality)
    }

    private var gender: SecretaryProfile.Gender {
        switch genderChoice {
        case .female: return .female
        case .male: return .male
        case .other: return .other(genderText)
        }
    }

    private var age: SecretaryProfile.Age {
        switch ageChoice {
        case .child: return .child
        case .teenager: return .teenager
        case .adult: return .adult
        case .exact:
            if let years = Int(ageText.trimmingCharacters(in: .whitespaces)), years > 0, years < 130 {
                return .years(years)
            }
            return .adult
        }
    }

    func hasChanges(from profile: SecretaryProfile) -> Bool {
        self.profile(id: profile.id) != profile
    }
}
