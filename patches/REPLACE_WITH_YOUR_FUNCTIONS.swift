/*
 *  REPLACE_WITH_YOUR_FUNCTIONS.swift
 *  Stub: nuSendFeedback (local-build no-op) for PreviewMarkdown 2.4.1+.
 *
 *  Upstream 2.4.1 moved the feedback API from a free function
 *  `sendFeedback(_:) -> URLSessionTask?` to an AppDelegate method
 *  `nuSendFeedback(_:) async -> FeedbackError` (defined nowhere upstream —
 *  this stub is its expected implementation). FeedbackError lives in
 *  Entities.swift (main-app target, same module).
 */

import Foundation

extension AppDelegate {

    func nuSendFeedback(_ feedback: String) async -> FeedbackError {

        return FeedbackError(code: .badSession)
    }
}
