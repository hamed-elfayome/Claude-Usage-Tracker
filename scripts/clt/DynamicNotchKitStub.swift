import SwiftUI
public struct DynamicNotchHoverBehavior: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let keepVisible = DynamicNotchHoverBehavior(rawValue: 1) }
public enum DynamicNotchStyle: Sendable { case auto, notch, floating }
@MainActor public final class DynamicNotch<Expanded: View, CompactLeading: View, CompactTrailing: View>: ObservableObject {
  public var isHovering: Bool = false
  public init(hoverBehavior: DynamicNotchHoverBehavior = [], style: DynamicNotchStyle = .auto, @ViewBuilder expanded: @escaping () -> Expanded, @ViewBuilder compactLeading: @escaping () -> CompactLeading, @ViewBuilder compactTrailing: @escaping () -> CompactTrailing) {}
  public func expand(on screen: NSScreen = NSScreen.screens[0]) async {}
  public func compact(on screen: NSScreen = NSScreen.screens[0]) async {}
  public func hide() async {}
}
