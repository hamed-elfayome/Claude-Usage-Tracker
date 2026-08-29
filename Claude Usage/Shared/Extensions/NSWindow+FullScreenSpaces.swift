//
//  NSWindow+FullScreenSpaces.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-08-18.
//

import Cocoa

// MARK: - Space Placement for Menu Bar Windows
extension NSWindow {
    /// Makes the window appear on every Space, including another app's full-screen Space.
    ///
    /// A status bar popover's backing window is created without a Spaces behavior, which
    /// leaves it associated with the one Space this accessory agent occupies.
    ///
    /// `NSPopover` has no backing window until it is first shown, so this has to be called
    /// on `contentViewController?.view.window` after `show(relativeTo:of:preferredEdge:)`.
    ///
    /// Collection behavior outside the Spaces group is preserved.
    func enableDisplayOnFullScreenSpaces() {
        // Setting both Spaces behaviors raises NSInternalInconsistencyException at runtime
        // (undocumented — the SDK only promises an assertion for the tiling pair), so the
        // conflicting one has to go before the new one is inserted.
        collectionBehavior.remove(.moveToActiveSpace)

        // `.canJoinAllSpaces` covers ordinary Spaces; a full-screen Space admits another
        // app's window only with `.fullScreenAuxiliary`, so both are required.
        collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
    }
}
