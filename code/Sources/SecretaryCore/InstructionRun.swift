import FunctionalCore
import Foundation

public struct InstructionRun: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case finished
        case halted(reason: String)
    }

    public let plan: InstructionPlan
    public let stepIndex: Int
    public let status: Status

    public init(plan: InstructionPlan, stepIndex: Int = 0, status: Status = .running) {
        self.plan = plan
        self.stepIndex = stepIndex
        self.status = status
    }

    public var isRunning: Bool { status == .running }

    public var currentStep: Option<String> {
        guard isRunning, stepIndex < plan.steps.count else { return .none() }
        return .some(plan.steps[stepIndex])
    }

    public var stepNumber: Int { stepIndex + 1 }

    public var totalSteps: Int { plan.steps.count }

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
