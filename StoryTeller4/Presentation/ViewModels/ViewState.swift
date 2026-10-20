import Foundation

// MARK: - ViewState
/// Represents a unified single-source-of-truth loading & content state for ViewModels.
enum ViewState<T: Equatable>: Equatable {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var value: T? {
        if case .loaded(let val) = self { return val }
        return nil
    }

    var errorMessage: String? {
        if case .failed(let err) = self { return err }
        return nil
    }
}
