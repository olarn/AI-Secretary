import LLMProvider

public func activityLine(_ step: AgentActivity) -> String {
    switch (step.kind, step.origin) {
    case (.thinking, .main): return "◇ \(step.detail)"
    case (.tool, .main): return "▸ \(step.detail)"
    case (.thinking, .subagent): return "   ◈ \(step.detail)"
    case (.tool, .subagent): return "   ▹ \(step.detail)"
    }
}
