import LLMProvider

/// One line of the "what I'm doing" box, marked by whose work it is.
///
/// A sub-agent's steps are indented under her own and carry a hollow marker:
/// the same kind of event, one level in, and not her doing. Until the stream was
/// read for `parent_tool_use_id` they were drawn identically to hers — so the
/// box said she had run a `Bash` command she had never run, and there was
/// nothing on screen that could have told anyone otherwise.
///
/// The marker is chosen here, in a library target, rather than inline where the
/// box is built: `AISecretaryApp` is invisible to coverage, and this is a rule
/// with four answers.
public func activityLine(_ step: AgentActivity) -> String {
    switch (step.kind, step.origin) {
    case (.thinking, .main): return "◇ \(step.detail)"
    case (.tool, .main): return "▸ \(step.detail)"
    case (.thinking, .subagent): return "   ◈ \(step.detail)"
    case (.tool, .subagent): return "   ▹ \(step.detail)"
    }
}
