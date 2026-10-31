import SwiftUI

extension Animation {
    /// Short state transition. Callers disable this when Reduce Motion is enabled.
    static var appSelection: Animation { .easeOut(duration: 0.15) }
}
