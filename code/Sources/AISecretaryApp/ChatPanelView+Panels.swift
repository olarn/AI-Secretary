import SwiftUI
import ProjectRegistry
import SecretaryCore

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

    private var characterScaleRow: some View {
        choiceRow("Character size", CharacterScale.allCases.map { scale in
            (scale.label, appearance.settings.characterScale == scale, { appearance.selectCharacterScale(scale) })
        })
    }

    private func choiceRow(
        _ label: String,
        _ options: [(title: String, isCurrent: Bool, choose: () -> Void)]
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing) {
            Text(label)
                .font(.system(size: appearance.settings.footnoteFontSize))
            Spacer(minLength: 0)
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.title, action: option.choose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: appearance.settings.hintFontSize))
                    .background(
                        option.isCurrent
                            ? AnyShapeStyle(theme.accent.color)
                            : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .foregroundStyle(
                        option.isCurrent ? theme.onAccent.color : theme.primaryText.color
                    )
                    .tint(option.isCurrent ? theme.onAccent.color : theme.primaryText.color)
            }
        }
    }

    private func stepperRow(
        label: String,
        value: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: appearance.settings.panelSpacing) {
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

            browserPicker
            Text(
                "Reads pages in your Chrome, including sites you're signed in to. "
                + "Needs the Claude in Chrome extension. Clicking and typing still ask first."
            )
            .font(.system(size: appearance.settings.hintFontSize))
            .foregroundStyle(theme.mutedText.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(appearance.settings.panelPadding)
        .background(PanelBoxGround(palette: theme, liquidGlass: appearance.settings.liquidGlass))
    }

    private var browserPicker: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
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
                        vendorStatus: vendorStatus,
                        secretary: secretary
                    )
                case .projects: projectsSection
                case .skills: skillsSection
                }
            }
            .frame(maxHeight: appearance.settings.chatHeight * Self.panelHeightShare)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let panelHeightShare: Double = 0.55

    private static let gripStrip: Double = 12

    var footer: some View {
        HStack(spacing: 10) {
            ForEach(Array(footerSlots().enumerated()), id: \.offset) { _, slot in
                switch slot {
                case .gap:
                    Spacer(minLength: 12)
                case .button(let button):
                    let panel = Panel(button)
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
        .padding(.bottom, gripCorner.isBottom ? Self.gripStrip : 0)
        .toggleStyle(PanelToggleStyle(
            fontSize: appearance.settings.secondaryFontSize,
            controlSize: appearance.settings.fontSize > 16 ? .regular : .small,
            palette: theme,
            liquidGlass: appearance.settings.liquidGlass
        ))
        .font(.system(size: appearance.settings.secondaryFontSize))
    }
}
