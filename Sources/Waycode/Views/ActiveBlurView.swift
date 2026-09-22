import AppKit
import SwiftUI

/// A permanently-active visual effect. SwiftUI Material changes emphasis when
/// the frontmost application or Space changes; this view deliberately does not.
struct ActiveBlurView: NSViewRepresentable {
    let style: BarBlurStyle

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: .darkAqua)
        view.alphaValue = 1
        view.material = material
    }

    private var material: NSVisualEffectView.Material {
        switch style {
        case .thin: .underWindowBackground
        case .regular: .hudWindow
        case .thick: .popover
        }
    }
}
