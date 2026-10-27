import AppKit

// Смена светлой и тёмной темы — мягким наплывом, как у самого macOS. Перед сменой оформления
// (KVO с .prior — уведомление приходит ещё до смены) снимаем каждое окно в старой теме, кладём снимок
// поверх уже перекрашенного окна и растворяем за полсекунды. Так плавно меняется всё сразу:
// стекло, планки, текст — даже то, что рисуется вручную (Canvas) и само анимироваться не умеет.
final class ThemeCrossfade {
    static let shared = ThemeCrossfade()
    private var observation: NSKeyValueObservation?
    private var snapshots: [(NSWindow, NSImageView)] = []

    func start() {
        observation = NSApp.observe(\.effectiveAppearance, options: [.prior]) { _, change in
            MainActor.assumeIsolated {
                if change.isPrior { ThemeCrossfade.shared.capture() } else { ThemeCrossfade.shared.fade() }
            }
        }
    }

    private func capture() {
        snapshots = NSApp.windows.compactMap { window in
            guard window.isVisible, let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(bitmap)
            let cover = NSImageView(frame: view.bounds)
            cover.image = image
            cover.imageScaling = .scaleAxesIndependently
            cover.autoresizingMask = [.width, .height]
            return (window, cover)
        }
    }

    private func fade() {
        for (window, cover) in snapshots {
            window.contentView?.addSubview(cover, positioned: .above, relativeTo: nil)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                cover.animator().alphaValue = 0
            }, completionHandler: { cover.removeFromSuperview() })
        }
        snapshots = []
    }
}
