import FunctionalCore
import Foundation

func asChatError(_ error: Error, otherwise fallback: (String) -> ChatError) -> ChatError {
    (error as? ChatError) ?? fallback(error.localizedDescription)
}
