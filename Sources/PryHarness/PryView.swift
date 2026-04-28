import Foundation
import SwiftUI

/// SwiftUI helpers that auto-(un)register `PryInspectable` view models with
/// `PryRegistry.shared` based on view lifecycle. Useful for VMs created
/// inside views (e.g. `@StateObject`) that aren't easily reachable from the
/// app's top-level scene where `PryRegistry.shared.register(_:)` is normally
/// called.
///
/// In RELEASE builds the helpers compile away if you wrap the call site in
/// `#if DEBUG` (which `PryHarness.start()` already requires).
///
/// Example:
///
/// ```swift
/// struct CommandPaletteView: View {
///     @StateObject private var vm = CommandPaletteVM()
///     var body: some View {
///         List(vm.commands) { ... }
///         #if DEBUG
///             .pryRegister(vm)
///         #endif
///     }
/// }
/// ```
public extension View {
    /// Register `instance` with `PryRegistry.shared` while this view is
    /// on-screen. Cleans up on disappear.
    @MainActor
    func pryRegister<T: PryInspectable>(_ instance: T) -> some View {
        self
            .task {
                PryRegistry.shared.register(instance)
            }
            .onDisappear {
                PryRegistry.shared.unregister(name: T.pryName)
            }
    }
}
