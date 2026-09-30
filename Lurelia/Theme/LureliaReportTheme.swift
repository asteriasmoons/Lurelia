//
//  LureliaReportTheme.swift
//  Lurelia
//
//  Compatibility layer for the ported Voxiverse report system. It forwards the
//  color/theme symbols the report UI expects onto Lurelia's existing LColors
//  palette, so the report screens render with Lurelia's real theme rather than
//  introducing a second design system.
//

import SwiftUI

// MARK: - Nested LColors members used by the report views

extension LColors {
    static let headingPrimary = LColors.textPrimary

    enum text {
        static let primary = LColors.textPrimary
        static let secondary = LColors.textSecondary
    }

    enum accents {
        static let primary = LColors.textPrimary
        static let secondary = LColors.textPrimary
        static let contrast = Color.white
    }

    enum surface {
        static let primary = LColors.glassSurface
        static let nested = LColors.glassSurface2
        static let elevated = Color.white.opacity(0.12)
    }

    enum iconContainer {
        static let primary = LColors.glassSurface
    }
}

// MARK: - Dismiss keyboard on tap (window-level, ignores taps on controls)

extension View {
    func lureliaDismissKeyboardOnTap() -> some View {
        background(LureliaKeyboardDismissTapInstaller())
    }
}

private struct LureliaKeyboardDismissTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = LureliaKeyboardDismissHostView()
        view.configure(coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? LureliaKeyboardDismissHostView)?.configure(coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func dismissKeyboard(_ recognizer: UITapGestureRecognizer) {
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView: UIView? = touch.view
            while let currentView = touchedView {
                if currentView is UIControl || currentView is UITextField || currentView is UITextView {
                    return false
                }
                touchedView = currentView.superview
            }
            return true
        }
    }
}

private final class LureliaKeyboardDismissHostView: UIView {
    private weak var coordinator: LureliaKeyboardDismissTapInstaller.Coordinator?
    private weak var installedWindow: UIWindow?
    private weak var tapRecognizer: UITapGestureRecognizer?

    func configure(coordinator: LureliaKeyboardDismissTapInstaller.Coordinator) {
        self.coordinator = coordinator
        installRecognizerIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installRecognizerIfNeeded()
    }

    deinit {
        if let tapRecognizer {
            installedWindow?.removeGestureRecognizer(tapRecognizer)
        }
    }

    private func installRecognizerIfNeeded() {
        guard let window, let coordinator else { return }
        if installedWindow === window, tapRecognizer != nil { return }
        if let tapRecognizer {
            installedWindow?.removeGestureRecognizer(tapRecognizer)
        }
        let recognizer = UITapGestureRecognizer(target: coordinator, action: #selector(LureliaKeyboardDismissTapInstaller.Coordinator.dismissKeyboard(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = coordinator
        window.addGestureRecognizer(recognizer)
        installedWindow = window
        tapRecognizer = recognizer
    }
}
