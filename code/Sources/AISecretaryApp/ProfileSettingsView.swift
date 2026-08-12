import SwiftUI
import AppKit
import AssistantState
import LLMProvider
import SecretaryCore

/// The Profile section of the settings panel: which secretary the app is
/// wearing, her details, her picture, and the brain she thinks with.
///
/// Model and Effort live here rather than in Settings because they are part of
/// who is answering, not part of how the window looks. Settings keeps the
/// things that change the app's appearance; this panel keeps the things that
/// change the secretary.
///
/// Selecting a profile takes effect immediately; the detail fields are edited in
/// a draft and committed with Save, because a text field that applied per
/// keystroke would announce a change in the conversation for every letter typed.
struct ProfileSettingsView: View {
    /// The colours in force, set by whichever window this view is inside.
    @Environment(\.palette) private var theme

    let profiles: ProfileLibrary
    let appearance: Appearance
    /// Only for the Model and Effort rows. They are settings of the running
    /// assistant rather than fields of the stored profile, which is why they
    /// take effect on click while everything above them waits for Save.
    let secretary: Secretary

    @State private var draft: Draft
    @State private var editingID: UUID
    @State private var note: String?

    init(profiles: ProfileLibrary, appearance: Appearance, secretary: Secretary) {
        self.profiles = profiles
        self.appearance = appearance
        self.secretary = secretary
        _draft = State(initialValue: Draft(profiles.active))
        _editingID = State(initialValue: profiles.active.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Text("Profile")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))

            profilePicker
            // A Grid, not a stack of HStacks with a fixed label column: the
            // labels have to line up, and the width they need changes with the
            // longest word and with the app size. "Personality" broke a 52pt
            // column the day it replaced "Style" — it wrapped mid-word — and
            // any number picked to fit it would break again at size L.
            Grid(alignment: .leading, horizontalSpacing: appearance.settings.panelSpacing, verticalSpacing: appearance.settings.panelSpacing) {
                nameField
                genderRow
                ageRow
                personalityField

                dividerRow
                pictureRow

                dividerRow
                modelRow
                effortRow
            }

            HStack(spacing: appearance.settings.panelSpacing) {
                Button("Save") { save() }
                    .buttonStyle(.bordered)
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .disabled(!draft.hasChanges(from: profiles.active))
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
        .background(theme.chipFill.color, in: RoundedRectangle(cornerRadius: 8))
        // Keeps the fields in step when the active profile changes from anywhere
        // else — a new profile, or a delete that fell back to another one.
        .onChange(of: profiles.activeID) { _, newID in
            if newID != editingID { loadActiveIntoDraft() }
        }
    }

    // MARK: - Rows

    private var profilePicker: some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Menu {
                ForEach(profiles.profiles) { profile in
                    Button {
                        profiles.activate(profile.id)
                        loadActiveIntoDraft()
                        note = nil
                    } label: {
                        Label(
                            profile.displayName,
                            systemImage: profile.id == profiles.activeID ? "checkmark" : ""
                        )
                    }
                }
                Divider()
                Button("New profile…") { createProfile() }
            } label: {
                Text(profiles.active.displayName)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
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
            HStack(spacing: appearance.settings.panelSpacing) {
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
                // Free text, as specified — anything beyond male and female is
                // the user's own words rather than a list they have to fit into.
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
            HStack(spacing: appearance.settings.panelSpacing) {
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
            // Beside two lines of content, a centred label floats between them
            // and stops reading as the name of the field above it.
            fieldLabel("Personality")
                .gridCellAnchor(.topLeading)
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

    /// One picture per profile. The same menu shape as the Model and Effort
    /// pickers, so choosing and clearing work the way the rest of the panel does.
    private var pictureRow: some View {
        let id = profiles.activeID
        let hasPicture = profiles.hasArtwork(for: id)

        return GridRow {
            fieldLabel("Picture")
                .gridCellAnchor(.topLeading)
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                HStack(spacing: appearance.settings.panelSpacing) {
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
                // Read from disk, so a change has to invalidate the label.
                .id("picture-\(profiles.artworkRevision)-\(id)")
                Spacer(minLength: 0)
                }
                Text("Shown in every state — the colour and badge say what she's doing.")
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
        }
    }

    /// Clicking the name opens a real picker. The same entry point the slash
    /// commands use, so a change here is announced in the transcript too — the
    /// conversation is where the change takes effect, so that's where it should
    /// be visible.
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
                        "Your Claude Code default",
                        systemImage: secretary.isModelInherited ? "checkmark" : ""
                    )
                }
                Divider()
                ForEach(ChatModel.known, id: \.id) { candidate in
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
                .gridCellAnchor(.topLeading)
            VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.35) {
                settingControl(
                    value: secretary.effectiveEffortName,
                    inherited: secretary.isEffortInherited
                ) {
                    Button {
                        secretary.chooseEffort(nil)
                    } label: {
                        Label(
                            "Your Claude Code default",
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
                // One hint for both rows, under the second of them, the way
                // Personality and Picture carry theirs in the content column.
                Text("Change with /model <id> or /effort <level> in the chat. The dashed ring marks one the app didn't pick, which can move if you reconfigure Claude Code.")
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A menu showing the value it is set to, with the inherited marker beside
    /// it rather than inside it.
    ///
    /// Outside the menu on purpose: a `Menu` label built from several views
    /// renders as the chevron alone here, which is why these two rows used to
    /// show their title and no value at all. The value is the one thing the row
    /// exists to say, so it is the only thing in the label.
    private func settingControl<Choices: View>(
        value: String,
        inherited: Bool,
        @ViewBuilder choices: () -> Choices
    ) -> some View {
        HStack(spacing: appearance.settings.panelSpacing * 0.5) {
            Menu(content: choices) {
                Text(value)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if inherited {
                Image(systemName: "circle.dashed")
                    .font(.system(size: appearance.settings.hintFontSize * 0.8))
                    .foregroundStyle(theme.mutedText.color)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: appearance.settings.footnoteFontSize))
            .foregroundStyle(theme.mutedText.color)
            // The grid gives the column the width of the widest label; this
            // only says the label itself must not be the thing that wraps.
            .lineLimit(1)
            .fixedSize()
    }

    /// A rule across both columns. `Divider()` on its own would sit inside the
    /// label column and draw a stub.
    private var dividerRow: some View {
        GridRow {
            Divider().gridCellColumns(2)
        }
    }

    // MARK: - Actions

    private func loadActiveIntoDraft() {
        draft = Draft(profiles.active)
        editingID = profiles.active.id
    }

    private func save() {
        profiles.update(draft.profile(id: editingID))
        note = nil
    }

    private func createProfile() {
        // Named provisionally rather than blocking on a picture: the built-in
        // avatar covers a profile with no artwork, and stopping to pick a file
        // before the profile exists is a worse first step.
        let existing = profiles.profiles.count + 1
        profiles.add(SecretaryProfile(name: "Secretary \(existing)"))
        loadActiveIntoDraft()
        note = "New profile — set the name and add a picture."
    }

    private func delete() {
        let name = profiles.active.displayName
        profiles.delete(profiles.activeID)
        loadActiveIntoDraft()
        note = "Deleted “\(name)”."
    }

    private func choosePicture() {
        guard let source = ImagePicker.promptForImage(
            message: "Choose a picture for \(profiles.active.displayName)."
        ) else { return }

        // Re-encoded to PNG so the stored file matches its name whatever the
        // user picked, and so an unreadable file is reported now rather than
        // showing up later as a blank character.
        guard let image = NSImage(contentsOf: source), let png = image.pngData else {
            note = "Couldn't read that image."
            return
        }
        note = profiles.setArtworkReportingProblem(pngData: png, for: profiles.activeID)
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

/// The editable copy of a profile. The menus need a plain choice plus its free
/// text, which the model's enums deliberately don't carry separately.
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

    /// An unparseable exact age falls back to a life stage rather than refusing
    /// the save — the field is a convenience, not a gate.
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
