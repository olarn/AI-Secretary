import FunctionalCore
import Foundation

/// A plan being carried out, one step at a time.
///
/// A value, not a mutable controller: where the run has got to is something the
/// view renders and a test can construct, and a second copy of that number
/// living in a class is the copy that drifts.
///
/// The run is pinned to the fingerprint the plan was made from. If the file
/// changes while it is going, the run halts and says so — it does not pick up
/// the new steps, and it does not silently finish the old ones. Somebody
/// editing the file mid-run has changed their mind; carrying on with either
/// version without asking would be the app deciding which.
public struct InstructionRun: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case finished
        /// Stopped before the end: the user cancelled, or the file changed.
        case halted(reason: String)
    }

    public let plan: InstructionPlan
    /// Which step comes next; equal to `plan.steps.count` when they're all done.
    public let stepIndex: Int
    public let status: Status

    public init(plan: InstructionPlan, stepIndex: Int = 0, status: Status = .running) {
        self.plan = plan
        self.stepIndex = stepIndex
        self.status = status
    }

    public var isRunning: Bool { status == .running }

    /// The step about to run, if there is one and the run is still going.
    public var currentStep: Option<String> {
        guard isRunning, stepIndex < plan.steps.count else { return .none() }
        return .some(plan.steps[stepIndex])
    }

    /// One-based, for people. `stepIndex` is zero-based, for arrays.
    public var stepNumber: Int { stepIndex + 1 }

    public var totalSteps: Int { plan.steps.count }

    /// Moves on. A run that has just used its last step is finished, so the
    /// caller never has to compare the index against the count itself.
    public func advancing() -> InstructionRun {
        guard isRunning else { return self }
        let next = stepIndex + 1
        return InstructionRun(
            plan: plan,
            stepIndex: next,
            status: next >= plan.steps.count ? .finished : .running
        )
    }

    public func halting(reason: String) -> InstructionRun {
        InstructionRun(plan: plan, stepIndex: stepIndex, status: .halted(reason: reason))
    }

    /// "Step 2 of 5 of deploy.md" — used in the announcement before each step
    /// and in `/run` status, so both say it the same way.
    public var progressDescription: String {
        switch status {
        case .running:
            return "Step \(stepNumber) of \(totalSteps) of \(plan.relativePath)"
        case .finished:
            return "Finished all \(totalSteps) steps of \(plan.relativePath)"
        case .halted(let reason):
            return "Stopped at step \(min(stepNumber, totalSteps)) of \(totalSteps) of \(plan.relativePath) — \(reason)"
        }
    }
}
