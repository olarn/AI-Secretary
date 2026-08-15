import SwiftUI
import AppKit
import AssistantState
import SecretaryCore

/// Desktop companion character. Displays a locally-provided character image
/// if the user has placed one (see `CharacterAsset`), otherwise falls back
/// to the built-in placeholder avatar; a small state badge and tap-to-open
/// remain the same either way.
struct CharacterView: View {
    let machine: AssistantStateMachine
    let secretary: Secretary
    let profiles: ProfileLibrary
    /// Whose face this is. Every character on the desktop draws her own, so the
    /// picture is looked up by id rather than by "whichever profile is active".
    let profileID: UUID
    let appearance: Appearance
    let onTap: () -> Void

    /// S/M/L is a whole-character zoom rather than a re-layout: the badge, the
    /// halo, and the bubble's tail are all positioned against each other, so
    /// scaling the finished view keeps them in the same relationship.
    ///
    /// `fixedSize` makes it take its own ideal size rather than whatever the
    /// window offers. The window is then sized from that ideal (see
    /// `AppDelegate.characterSize`): sized the other way round, a window even a
    /// few points too small clipped the halo into a flat edge across the top of
    /// the character's head.
    var body: some View {
        content
            .fixedSize()
            .scaleEffect(appearance.settings.characterScale.factor)
    }

    private var content: some View {
        VStack(spacing: 6) {
            // Centred, so the character sits in the middle of its halo whatever
            // shape the picture is. The badge is an overlay rather than a third
            // layer in here: aligning the stack to the corner for the badge's
            // sake pushed the character over with it, by however much narrower
            // than the halo it happened to be.
            ZStack {
                halo

                characterArt
            }
            // The status badge doubles as the switch for the running
            // commentary: it already shows what the assistant is doing, so
            // it's the natural place to ask for more or less of it.
            .overlay(alignment: .bottomTrailing) {
                Button(action: secretary.toggleActivityVisibility) {
                    StatusBadge(state: machine.state)
                        .opacity(secretary.showsActivity ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .help(secretary.showsActivity ? "Hide what I'm doing" : "Show what I'm doing")
                .offset(x: 2, y: 2)
            }
            .shadow(radius: 6)

            // Who this is, and what they're doing when that's anything. It read
            // "IDLE" almost always, which named a state nobody was waiting on
            // and never said whose desktop companion it was.
            Text(characterStatusLabel(name: secretary.profile.displayName, state: machine.state))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// The ring the character stands in, which is also where "she is thinking"
    /// is said loudest — it is the largest thing on the desktop that can change
    /// colour, and the owner asked for the blink to be the whole frame rather
    /// than the badge alone.
    ///
    /// Grey at rest, the state's colour at full stretch, on the same clock as
    /// the badge. Same clock, not a shared flag: both read `pulseProgress` from
    /// the current time, so they cannot drift apart however long they run.
    ///
    /// The halo does not scale. It is the frame the character sits in, and a
    /// frame that changes size drags the character's edges with it.
    ///
    /// Deliberately its own `TimelineView`, wrapping only this circle: the one
    /// above it would rebuild `characterArt` thirty times a second, and that
    /// reads the picture off disk.
    private var halo: some View {
        let pulse = statusPulse(for: machine.state)
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulse.isAnimated)) { context in
            let progress = pulseProgress(pulse, at: context.date.timeIntervalSinceReferenceDate)
            Circle()
                .fill((pulse.isAnimated ? Color.gray : stateColor(for: machine.state)).opacity(0.25))
                .overlay(Circle().fill(stateColor(for: machine.state).opacity(0.25 * progress)))
                .frame(width: 104, height: 104)
        }
        .frame(width: 104, height: 104)
    }

    /// This character's picture, falling back to the legacy drop-in file and
    /// then to the built-in avatar. A profile with no picture at all is normal,
    /// so the last fallback has to hold up on its own.
    @ViewBuilder
    private var characterArt: some View {
        if let nsImage = artworkImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 104)
        } else {
            MikuAvatarView()
        }
    }

    private var artworkImage: NSImage? {
        // Read the revision so an upload or a profile switch invalidates this.
        _ = profiles.artworkRevision
        if let url = profiles.artworkFileURL(for: profileID), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(contentsOf: CharacterAsset.url)
    }

    private func stateColor(for state: AssistantState) -> Color {
        switch state {
        case .idle: return .gray
        case .listening: return .blue
        case .thinking: return .purple
        case .working: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}

/// A user-supplied character image, loaded from outside the git repo so
/// licensed/copyrighted art never gets committed or distributed with the
/// project. Drop a PNG at this path to override the built-in placeholder;
/// remove it to fall back automatically.
enum CharacterAsset {
    static var url: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("character.png")
    }
}
