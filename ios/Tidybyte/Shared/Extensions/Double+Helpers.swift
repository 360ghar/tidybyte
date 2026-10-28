import Foundation

extension Double {
    func nonZeroOr(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}
