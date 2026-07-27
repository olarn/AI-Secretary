import SwiftUI
import AppKit
import AssistantState
import SecretaryCore

/// The Profile section of the settings panel: which secretary the app is
/// wearing, her details, and her pictures.
///
/// Selecting a profile takes effect immediately; the detail fields are edited in
/// a draft and committed with Save, because a text field that applied per
/// keystroke would announce a change in the conversation for every letter typed.
struct ProfileSettingsView: View {
    let profiles: ProfileLibrary
    let appearance: Appearance

    @State private var draft: Draft
    @State private var editingID: UUID
    @State private var note: String?

    init(profiles: ProfileLibrary, appearance: Appearance) {
        self.profiles = profiles
        self.appearance = appearance
        _draft = State(initialValue: Draft(profiles.active))
        _editingID = State(initialValue: profiles.active.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Profile")
                .font(.caption.bold())

            profilePicker
            nameField
            genderRow
            ageRow
            styleField

            Divider()
            picturesSection

            Divider()
            appSizeRow

            HStack(spacing: 6) {
                Button("Save") { save() }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .disabled(!draft.hasChanges(from: profiles.active))
                if profiles.canDelete {
                    Button("Delete") { delete() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let note {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        // Keeps the fields in step when the active profile changes from anywhere
        // else — a new profile, or a delete that fell back to another one.
        .onChange(of: profiles.activeID) { _, newID in
            if newID != editingID { loadActiveIntoDraft() }
        }
    }

    // MARK: - Rows

    private var profilePicker: some View {
        HStack(spacing: 6) {
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
        .font(.caption2)
    }

    private var nameField: some View {
        HStack(spacing: 6) {
            fieldLabel("Name")
            TextField("Miku", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
        }
    }

    private var genderRow: some View {
        HStack(spacing: 6) {
            fieldLabel("Gender")
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
                    .font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
    }

    private var ageRow: some View {
        HStack(spacing: 6) {
            fieldLabel("Age")
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
                    .font(.caption2)
                    .frame(width: 44)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
    }

    private var styleField: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                fieldLabel("Style")
                TextField(SecretaryProfile.defaultStyle, text: $draft.style)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
            }
            Text("Free text — how she should sound. Blank means \(SecretaryProfile.defaultStyle).")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    /// One required picture, plus optional ones per state. Anything missing
    /// falls back to the default picture, and a profile with no pictures at all
    /// keeps the built-in avatar.
    ///
    /// Laid out as chips flowing left-to-right and wrapping, each opening a menu
    /// on click — the same shape as the Model and Effort pickers. Seven full-width
    /// rows of buttons made the section taller than the panel; this fits in two.
    private var picturesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pictures")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Fixed rows rather than a LazyVGrid: a lazy container collapses to
            // nothing when the panel proposes it a squeezed height, which is
            // exactly what happens with a section open in a fixed-height bubble.
            ForEach(Array(Self.chipRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.label) { chip in
                        pictureChip(state: chip.state, label: chip.label)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Only the default is needed — states without a picture use it.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    /// One chip per picture slot, wrapped into rows: the default first, then the
    /// states in lifecycle order, left to right and top to bottom.
    private struct Chip {
        let state: AssistantState?
        let label: String
    }

    private static let chipRows: [[Chip]] = {
        let chips = [Chip(state: nil, label: "Default")]
            + ProfileArtwork.artworkStates.map {
                Chip(state: $0, label: $0.rawValue.capitalized)
            }
        return stride(from: 0, to: chips.count, by: 3).map {
            Array(chips[$0..<min($0 + 3, chips.count)])
        }
    }()

    private func pictureChip(state: AssistantState?, label: String) -> some View {
        let id = profiles.activeID
        let hasPicture = state.map { profiles.statesWithArtwork(for: id).contains($0) }
            ?? profiles.hasDefaultArtwork(for: id)

        return Menu {
            Button(hasPicture ? "Replace picture…" : "Choose picture…") {
                choosePicture(for: state)
            }
            if hasPicture {
                Button("Clear") { profiles.clearArtwork(state: state, for: id) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: hasPicture ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 8))
                    .foregroundStyle(hasPicture ? Color.green : .secondary)
                Text(label)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // The checkmarks are read from disk, so a change has to invalidate them.
        .id("\(label)-\(profiles.artworkRevision)-\(id)")
    }

    private var appSizeRow: some View {
        HStack(spacing: 6) {
            fieldLabel("App size")
            Spacer(minLength: 4)
            ForEach(AppScale.allCases, id: \.rawValue) { scale in
                Button(scale.label) { appearance.selectAppScale(scale) }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .disabled(appearance.settings.appScale == scale)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
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

    private func choosePicture(for state: AssistantState?) {
        let what = state.map { "the \($0.rawValue) state" } ?? "\(profiles.active.displayName)"
        guard let source = ImagePicker.promptForImage(message: "Choose a picture for \(what).")
        else { return }

        // Re-encoded to PNG so the stored file matches its name whatever the
        // user picked, and so an unreadable file is reported now rather than
        // showing up later as a blank character.
        guard let image = NSImage(contentsOf: source), let png = image.pngData else {
            note = "Couldn't read that image."
            return
        }
        do {
            try profiles.setArtwork(pngData: png, state: state, for: profiles.activeID)
            note = nil
        } catch {
            note = "Couldn't save that image: \(error.localizedDescription)"
        }
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
    var style: String

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
        style = profile.style
    }

    func profile(id: UUID) -> SecretaryProfile {
        SecretaryProfile(id: id, name: name, age: age, gender: gender, style: style)
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
