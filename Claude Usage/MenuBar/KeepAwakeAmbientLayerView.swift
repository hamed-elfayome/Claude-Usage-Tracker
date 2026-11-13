//
//  KeepAwakeAmbientLayerView.swift
//  Claude Usage
//
//  Core Animation-driven ambience for the keep-awake header button: a soft
//  breathing glow behind the cup and three steam wisps drifting up from it.
//
//  These loops were originally SwiftUI `.repeatForever` animations. A looping
//  SwiftUI animation re-renders the popover's NSHostingView on every display
//  frame (up to 120 Hz on ProMotion) for as long as the popover is open, and
//  each pass also re-measures the NSPopover frame — measured at 25–37% of a
//  core in a Debug build. CAAnimations are committed once and then run on the
//  render server, so the main thread does no per-frame work at all.
//

import AppKit
import SwiftUI

/// SwiftUI wrapper. Sized by the caller (24×24 to match the button).
struct KeepAwakeAmbientLayerView: NSViewRepresentable {
    /// When false (Reduce Motion), a static glow is drawn and steam is hidden.
    var animates: Bool

    func makeNSView(context: Context) -> KeepAwakeAmbientNSView {
        let view = KeepAwakeAmbientNSView()
        view.animates = animates
        return view
    }

    func updateNSView(_ nsView: KeepAwakeAmbientNSView, context: Context) {
        nsView.animates = animates
    }
}

final class KeepAwakeAmbientNSView: NSView {
    var animates = true {
        didSet { if animates != oldValue { rebuildAnimations() } }
    }

    private let glowLayer = CAGradientLayer()
    private var steamLayers: [CALayer] = []
    private var occlusionObserver: NSObjectProtocol?

    // Matches the original SwiftUI steam: 2.5pt dots at x offsets −2.5 / 0.5 / 3,
    // each rising from y −5 to −12 while fading 0.5 → 0 over 1.7s, staggered.
    private static let steamSpecs: [(x: CGFloat, delay: CFTimeInterval)] = [
        (-2.5, 0.0), (0.5, 0.55), (3.0, 1.1),
    ]
    private static let steamDuration: CFTimeInterval = 1.7
    private static let glowDuration: CFTimeInterval = 2.0
    private static let glowDiameter: CGFloat = 22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    /// y-down so layer offsets read like the SwiftUI `.offset` values they replace.
    override var isFlipped: Bool { true }

    /// Purely decorative; never intercept the button's clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Layers

    private func setupLayers() {
        guard let layer else { return }

        glowLayer.type = .radial
        glowLayer.colors = [
            NSColor.systemOrange.withAlphaComponent(0.5).cgColor,
            NSColor.systemOrange.withAlphaComponent(0.0).cgColor,
        ]
        glowLayer.locations = [0, 1]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        glowLayer.bounds = CGRect(x: 0, y: 0, width: Self.glowDiameter, height: Self.glowDiameter)
        layer.addSublayer(glowLayer)

        for _ in Self.steamSpecs {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 2.5, height: 2.5)
            dot.cornerRadius = 1.25
            dot.backgroundColor = NSColor.systemOrange.cgColor
            dot.opacity = 0 // invisible until its animation begins
            layer.addSublayer(dot)
            steamLayers.append(dot)
        }
    }

    private func positionLayers() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.position = center
        for (dot, spec) in zip(steamLayers, Self.steamSpecs) {
            dot.position = CGPoint(x: center.x + spec.x, y: center.y - 5)
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        positionLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        glowLayer.contentsScale = scale
        steamLayers.forEach { $0.contentsScale = scale }
    }

    // MARK: - Animations

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window {
            // Don't keep the render server busy for a popover that's off-screen.
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.rebuildAnimations()
            }
        }
        rebuildAnimations()
    }

    private func rebuildAnimations() {
        glowLayer.removeAllAnimations()
        steamLayers.forEach { $0.removeAllAnimations() }

        guard let window, window.occlusionState.contains(.visible) else {
            return
        }
        positionLayers()

        guard animates else {
            // Reduce Motion: steady glow, no steam.
            glowLayer.opacity = 0.7
            steamLayers.forEach { $0.opacity = 0 }
            return
        }

        glowLayer.opacity = 1
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.45
        pulse.toValue = 1.0
        pulse.duration = Self.glowDuration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(pulse, forKey: "pulse")

        let now = CACurrentMediaTime()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (dot, spec) in zip(steamLayers, Self.steamSpecs) {
            dot.opacity = 0

            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = center.y - 5
            rise.toValue = center.y - 12

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.5
            fade.toValue = 0.0

            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = Self.steamDuration
            group.beginTime = now + spec.delay
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dot.add(group, forKey: "steam")
        }
    }
}
