import SwiftUI
import ProjectRegistry
import SecretaryCore

/// The collapsible configuration sections and the footer that opens them:
/// Settings, Projects (with the browser switch), Skills, and the height cap
/// that makes the panel structurally incapable of overflowing.
extension ChatPanelView {
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Text("Settings")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))

            themeRow

            liquidGlassRow

            characterScaleRow

            fontRow

            stepperRow(
                label: "Text size",
                value: "\(Int(appearance.settings.fontSize))pt",
                canDecrease: appearance.settings.canDecreaseFontSize,
                canIncrease: appearance.settings.canIncreaseFontSize,
                onDecrease: appearance.decreaseFontSize,
                onIncrease: appearance.increaseFontSize
            )
            stepperRow(
                label: "Chat height",
                value: "\(Int(appearance.settings.chatHeight))pt",
                canDecrease: appearance.settings.canDecreaseHeight,
                canIncrease: appearance.settings.canIncreaseHeight,
                onDecrease: appearance.decreaseHeight,
                onIncrease: appearance.increaseHeight
            )
            Text("Or drag the grip in the corner away from the tail to size it freely — the tail stays on \(secretary.profile.displayName) either way.")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(theme.mutedText.color)

            if let settingsNote {
                Text(settingsNote)
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }
        }
        .padding(appearance.settings.panelPadding)
        .background(PanelBoxGround(palette: theme, liquidGlass: appearance.settings.liquidGlass))
    }

    /// Built from `ThemeChoice.allCases`, so adding a theme adds a button
    /// without this row being touched.
    private var themeRow: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.5) {
            choiceRow("Theme", ThemeChoice.allCases.map { choice in
                (choice.label, appearance.settings.theme == choice, { appearance.selectTheme(choice) })
            })
            Text(appearance.settings.theme.explanation)
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(theme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A checkbox rather than a fourth theme button: glass is a surface the
    /// bubble is drawn as, and it composes with all three theme choices — the
    /// palette still decides every colour, glass only replaces the ground it
    /// sits on. A fourth button would have made "Dark + glass" unsayable.
    private var liquidGlassRow: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.5) {
            Toggle("Liquid Glass", isOn: Binding(
                get: { appearance.settings.liquidGlass },
                set: { appearance.setLiquidGlass($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: appearance.settings.footnoteFontSize))
            Text("Draws the bubble as glass over your desktop. Works with every Theme above.")
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(theme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Built from `FontChoice.allCases`, the same way the theme row is.
    ///
    /// Sits above Text size because the two are read together and the face is
    /// the coarser choice of the pair: which font, then how big.
    private var fontRow: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.5) {
            choiceRow("Font", FontChoice.allCases.map { choice in
                (choice.label, appearance.settings.font == choice, { appearance.selectFont(choice) })
            })
            Text(appearance.settings.font.explanation)
                .font(.system(size: appearance.settings.hintFontSize))
                .foregroundStyle(theme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// It was called "App size" while there was one character and every setting
    /// was the app's. It only ever scaled the character, and now that each has
    /// her own it scales exactly one of them, so the old name described neither
    /// what it does nor who it does it to. (It sat in Profile before that,
    /// which was wrong for the opposite reason: with one character at a time,
    /// switching secretary would have resized the app under you.)
    private var characterScaleRow: some View {
        choiceRow("Character size", CharacterScale.allCases.map { scale in
            (scale.label, appearance.settings.characterScale == scale, { appearance.selectCharacterScale(scale) })
        })
    }

    /// Shared by Theme and App size because they are the same row, and because
    /// they sit next to each other: App size used to mark its current value by
    /// disabling that button, so two adjacent rows said "this is the one you're
    /// on" in two different ways, one of them indistinguishable from "you can't
    /// have this".
    private func choiceRow(
        _ label: String,
        _ options: [(title: String, isCurrent: Bool, choose: () -> Void)]
    ) -> some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Text(label)
                .font(.system(size: appearance.settings.footnoteFontSize))
            Spacer(minLength: 0)
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.title, action: option.choose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: appearance.settings.hintFontSize))
                    // Drawn here rather than left to the bordered style's own
                    // tint, for the reason in `PanelToggleStyle`: this window is
                    // never key, and AppKit greys out a tinted control in a
                    // window that isn't.
                    .background(
                        option.isCurrent
                            ? AnyShapeStyle(theme.accent.color)
                            : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .foregroundStyle(
                        option.isCurrent ? theme.onAccent.color : theme.primaryText.color
                    )
                    // See `PanelToggleStyle`: a bordered button's label follows
                    // the tint, not the foreground style.
                    .tint(option.isCurrent ? theme.onAccent.color : theme.primaryText.color)
            }
        }
    }

    /// A button that can't do anything is disabled rather than silently
    /// ignored, so reaching a limit reads as a limit.
    private func stepperRow(
        label: String,
        value: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack(spacing: appearance.settings.panelSpacing) {
            Text(label)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .foregroundStyle(theme.mutedText.color)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: appearance.settings.footnoteFontSize, design: .monospaced))
                .frame(minWidth: 38, alignment: .trailing)
            Button("−", action: onDecrease)
                .buttonStyle(.bordered)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .disabled(!canDecrease)
            Button("+", action: onIncrease)
                .buttonStyle(.bordered)
                .font(.system(size: appearance.settings.footnoteFontSize))
                .disabled(!canIncrease)
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            Text("Projects")
                .font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))

            if registry.projects.isEmpty {
                Text("None registered. Add one to let me work in it.")
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }

            ForEach(registry.projects) { project in
                HStack(spacing: appearance.settings.panelSpacing) {
                    VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.25) {
                        Text(project.name).font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                        Text(project.path)
                            .font(.system(size: appearance.settings.hintFontSize, design: .monospaced))
                            .foregroundStyle(theme.mutedText.color)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    Button {
                        addProjectNote = registry.removeReportingProblem(id: project.id)
                        // Taking a project away is the same event as adding
                        // one, and the half that matters more: the running
                        // session keeps the working directory it was given
                        // until something re-scopes it, so without this the
                        // assistant goes on working in a folder that is no
                        // longer approved.
                        secretary.projectsDidChange()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.mutedText.color)
                }
            }

            Button("Add project…") {
                addProjectNote = nil
                guard let project = ProjectPicker.promptForProject() else { return }
                addProjectNote = registry.addReportingProblem(project)
                // Adding a project mid-conversation is almost always a
                // correction to the question already asked, so the Secretary
                // re-scopes the workspace and runs it again.
                secretary.projectsDidChange()
            }
            .buttonStyle(.bordered)
            .font(.system(size: appearance.settings.footnoteFontSize))

            if let addProjectNote {
                Text(addProjectNote)
                    .font(.system(size: appearance.settings.hintFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }

            Divider()

            // Under Projects rather than Settings: the browser is somewhere the
            // assistant is allowed to read, which is the same kind of thing as
            // a project folder. Settings is what the app looks like.
            browserPicker
            Text(
                "Reads pages in your Chrome, including sites you're signed in to. "
                + "Needs the Claude in Chrome extension. Clicking and typing still ask first."
            )
            .font(.system(size: appearance.settings.hintFontSize))
            .foregroundStyle(theme.mutedText.color)
            // Two lines rather than one truncated one: the sentence about
            // reading signed-in sites is the part a person needs before they
            // switch this on, and "…" is where it was being cut.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(appearance.settings.panelPadding)
        .background(PanelBoxGround(palette: theme, liquidGlass: appearance.settings.liquidGlass))
    }

    /// A menu rather than a toggle switch, so this is a deliberate pick from a
    /// list and not a switch brushed by accident.
    private var browserPicker: some View {
        HStack(spacing: 3) {
            // Outside the menu on purpose. A menu label built from several
            // views renders as the chevron alone here, and the one thing this
            // row has to say is whether the browser is connected. Model and
            // Effort, over in Profile, are drawn the same way for the same
            // reason — see `settingControl` there.
            Text("Browser:").foregroundStyle(theme.mutedText.color)
            browserMenu
        }
        .font(.system(size: appearance.settings.footnoteFontSize))
    }

    private var browserMenu: some View {
        Menu {
            Button {
                secretary.setBrowserEnabled(false)
            } label: {
                Label("Off", systemImage: secretary.browserEnabled ? "" : "checkmark")
            }
            Button {
                secretary.setBrowserEnabled(true)
            } label: {
                Label("Read my browser", systemImage: secretary.browserEnabled ? "checkmark" : "")
            }
        } label: {
            Text(secretary.browserEnabled ? "Connected" : "Off")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Checkboxes rather than a menu: unlike Model/Effort, this is a
    /// multi-select, and a `Menu` closes after every tap — wrong for checking
    /// several boxes in one visit.
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: appearance.settings.panelSpacing) {
            HStack {
                Text("Skills").font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                Spacer()
                Button {
                    secretary.refreshAvailableSkills()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.mutedText.color)
                .help("Rescan for installed skills")
            }

            if secretary.availableSkills.isEmpty {
                Text("None found — checked ~/.claude/skills, this project's .claude/skills, and your enabled plugins.")
                    .font(.system(size: appearance.settings.footnoteFontSize))
                    .foregroundStyle(theme.mutedText.color)
            }

            ForEach(secretary.availableSkills) { skill in
                Toggle(isOn: Binding(
                    get: { secretary.selectedSkills.contains(skill.id) },
                    set: { _ in secretary.toggleSkill(skill.id) }
                )) {
                    VStack(alignment: .leading, spacing: appearance.settings.panelSpacing * 0.25) {
                        Text(skill.name).font(.system(size: appearance.settings.footnoteFontSize, weight: .semibold))
                        if !skill.summary.isEmpty {
                            Text(skill.summary)
                                .font(.system(size: appearance.settings.hintFontSize))
                                .foregroundStyle(theme.mutedText.color)
                                .lineLimit(2)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }

            // Says what checking does now, which is the opposite of what it used
            // to do: it asks for these to be preferred rather than shutting the
            // others off. The old wording promised a limit, which was both
            // unenforceable and not the thing anyone wanted from a checkbox.
            Text(
                secretary.selectedSkills.isEmpty
                    ? "Nothing checked — I'll reach for whichever installed skill fits."
                    : "I'll prefer these when they fit. Others stay available, and naming one in your message is still the sure way."
            )
            .font(.system(size: appearance.settings.hintFontSize))
            .foregroundStyle(theme.mutedText.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(appearance.settings.panelPadding)
        .background(PanelBoxGround(palette: theme, liquidGlass: appearance.settings.liquidGlass))
    }

    /// Held to a share of the window and given its own scroll, which is what
    /// makes the panel structurally incapable of overflowing.
    /// The
    /// surrounding `VStack` has exactly one flexible child — the transcript —
    /// and once that has shrunk to nothing, any further content simply spills
    /// past the bubble: the header goes off the top, the buttons off the
    /// bottom. Adding a row used to be enough to cross that line, so the fix
    /// cannot be a re-tuned constant. A section that can never be taller than
    /// its share, and scrolls when it wants to be, can never cross it at all.
    ///
    /// The share is a fraction of the real window height rather than "window
    /// minus the header, input and footer": those three grow with the text
    /// size, so any subtraction of them is a constant that goes stale the next
    /// time ⌘+ is pressed.
    @ViewBuilder
    var openPanelSection: some View {
        if let panel = openPanel {
            ScrollView(.vertical) {
                switch panel {
                case .settings: settingsSection
                case .profile:
                    ProfileSettingsView(
                        profiles: profiles,
                        profileID: profileID,
                        appearance: appearance,
                        secretary: secretary
                    )
                case .projects: projectsSection
                case .skills: skillsSection
                }
            }
            // A ScrollView takes every point it is offered, so a short panel —
            // Projects with nothing registered, Settings at a small text size —
            // claimed the whole allowance and left dead space between the box
            // and the buttons. Asking for the content's own height first, then
            // capping, makes the panel as tall as it needs and no taller, and
            // it still scrolls once the content passes the cap.
            .frame(maxHeight: appearance.settings.chatHeight * Self.panelHeightShare)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Leaves the rest of the window — header, transcript, input row and the
    /// section buttons — the larger share at every text size.
    private static let panelHeightShare: Double = 0.55

    /// The strip along the bottom of the window that belongs to the resize
    /// grip, on the placements where the grip is down here at all.
    ///
    /// The grip is 9pt of glyph inside 10pt of padding, and that padding is its
    /// hit area, not just air: it reaches about 30pt up from the bottom edge.
    /// The window's own 18pt sits under the row already, so this is the rest of
    /// what holds the row above it — and the margin is only a few points, which
    /// is why it is written down. Shrink either number and the corner of
    /// Projects lands inside the grip, where a click resizes the window instead
    /// of opening the pane and no screenshot shows it. Both bottom corners were
    /// checked by clicking the outermost pixel of the button in them.
    private static let gripStrip: Double = 12

    /// The section toggles grow with the text size like everything else in the
    /// panel: left at a fixed caption size they became unreadable specks next to
    /// 32pt replies. `controlSize` follows suit, or the button's own padding
    /// stays mini around text that isn't.
    var footer: some View {
        HStack(spacing: 10) {
            // The one row in the window that doesn't follow the bubble: these
            // four stay put so they can be aimed at without looking.
            ForEach(Array(footerSlots().enumerated()), id: \.offset) { _, slot in
                switch slot {
                case .gap:
                    Spacer(minLength: 12)
                case .button(let button):
                    let panel = Panel(button)
                    // Still a toggle each, and clicking the open one still
                    // closes it — opening one closes whichever was open.
                    Toggle(
                        button.title,
                        isOn: Binding(
                            get: { openPanel == panel },
                            set: { openPanel = $0 ? panel : nil }
                        )
                    )
                }
            }
        }
        // Both ends of this row hold a button, so the grip can't be dodged
        // sideways — it is given the strip underneath instead. Projects stays
        // against the left edge and Settings against the right, which is the
        // row as drawn; indenting whichever end the grip was in moved a button
        // every time the bubble flipped.
        //
        // Only when the grip is actually down here: with it at a top corner the
        // strip would be a gap under the row holding nothing.
        .padding(.bottom, gripCorner.isBottom ? Self.gripStrip : 0)
        // Not `.toggleStyle(.button)`: an accent-tinted control loses its colour
        // whenever the window isn't key, and this window is never key. See
        // `PanelToggleStyle`, which keeps the bordered metrics and changes only
        // how "this one is open" is drawn.
        .toggleStyle(PanelToggleStyle(
            fontSize: appearance.settings.secondaryFontSize,
            controlSize: appearance.settings.fontSize > 16 ? .regular : .small,
            palette: theme,
            liquidGlass: appearance.settings.liquidGlass
        ))
        .font(.system(size: appearance.settings.secondaryFontSize))
    }
}
