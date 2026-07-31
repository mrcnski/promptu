import SwiftUI

/// One keyed press-flash lamp: `lit` names the badge or hint wearing
/// the confirmation green right now, nil when none is. Cancel-and-rearm
/// on every fire, so a run of presses keeps the latest key lit for its
/// full beat. A timed blink has no instant equivalent, so with
/// animations off `fire` does nothing rather than passing through
/// `Motion.gated`.
@MainActor
final class Flash: ObservableObject {
    /// How long a flash holds before snapping back.
    static let duration: TimeInterval = 0.3

    @Published private(set) var lit: String?
    private var revert: DispatchWorkItem?

    func fire(_ key: String) {
        guard Motion.enabled else { return }
        revert?.cancel()
        lit = key
        let work = DispatchWorkItem { [weak self] in
            self?.lit = nil
            self?.revert = nil
        }
        revert = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }
}

/// The chrome shared by every flashing footer control: a solid
/// success chip while lit, the disabled dim otherwise — with the dim
/// held off through the flash, so a press that disables its own hint
/// (the last ⌫, the final ⌘Z) shows its full-strength beat before
/// the gray lands.
struct HintFlashChrome: ViewModifier {
    let theme: Theme
    let lit: Bool
    let available: Bool

    func body(content: Content) -> some View {
        content
            .background(lit ? theme.success : .clear, in: RoundedRectangle(cornerRadius: 4))
            .opacity(available || lit ? 1 : 0.4)
            .allowsHitTesting(available)
    }
}
