import PromptuCore
import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate for dragging one block over another: the list reorders
/// live as the drag moves (each step already saved by the Session), so
/// the drop itself only ends the drag. Used by both the editor list and
/// the composer grid.
struct BlockReorderDelegate: DropDelegate {
    let targetKey: String
    @Binding var draggingKey: String?
    let session: Session

    func dropEntered(info: DropInfo) {
        guard let key = draggingKey else { return }
        session.moveBlock(key, over: targetKey)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingKey = nil
        return true
    }
}

extension View {
    /// Make a block row/cell draggable and a drop target for reordering.
    func blockReorderable(
        _ block: Block, draggingKey: Binding<String?>, session: Session
    ) -> some View {
        onDrag {
            draggingKey.wrappedValue = block.key
            return NSItemProvider(object: block.key as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: BlockReorderDelegate(
                targetKey: block.key, draggingKey: draggingKey, session: session))
    }
}
