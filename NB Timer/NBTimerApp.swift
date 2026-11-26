//
//  NBTimerApp.swift
//  NB Timer
//

import Cocoa
import ServiceManagement

@main
enum NBTimerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State: String {
        case stopped, running, paused
    }

    private enum Key {
        static let state = "stopwatchState"
        static let accumulated = "stopwatchAccumulated"
        static let startTime = "stopwatchStartTime"
        static let countdown = "stopwatchCountdown"
    }

    private static let countdownPresets: [TimeInterval] = [45 * 60, 60 * 60, 2 * 60 * 60, 3 * 60 * 60]

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var state: State = .stopped
    private var startTime: Date?
    private var accumulated: TimeInterval = 0
    /// Length of the current countdown; 0 means the stopwatch counts up.
    private var countdown: TimeInterval = 0
    private var displaysAsleep = false
    private var lastDisplayText: String?

    // MARK: - LIFECYCLE

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLaunchAtLoginIfNeeded()
        observeDisplayPower()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.target = self
            button.action = #selector(openMenu)
        }

        restoreState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
    }

    private func registerLaunchAtLoginIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            print("Failed to register launch at login: \(error.localizedDescription)")
        }
    }

    private func observeDisplayPower() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(displayDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displayDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func displayDidSleep() {
        displaysAsleep = true
        stopTimer()
    }

    @objc private func displayDidWake() {
        displaysAsleep = false
        if state == .running { startTimer() }
        updateDisplay()
    }

    // MARK: - STATE PERSISTENCE

    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(state.rawValue, forKey: Key.state)
        defaults.set(accumulated, forKey: Key.accumulated)
        defaults.set(startTime, forKey: Key.startTime)
        defaults.set(countdown, forKey: Key.countdown)
    }

    private func restoreState() {
        let defaults = UserDefaults.standard
        state = defaults.string(forKey: Key.state).flatMap(State.init) ?? .stopped
        accumulated = defaults.double(forKey: Key.accumulated)
        startTime = defaults.object(forKey: Key.startTime) as? Date
        countdown = defaults.double(forKey: Key.countdown)

        if state == .running { startTimer() }
        updateDisplay()
    }

    // MARK: - MENU

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        switch state {
        case .stopped:
            menu.addItem(item("start", symbol: "play.fill", action: #selector(start)))
            menu.addItem(.separator())
            let header = NSMenuItem(title: NSLocalizedString("count_down", comment: ""), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for preset in Self.countdownPresets {
                let presetItem = item(presetTitle(preset), symbol: "timer", action: #selector(startCountdown(_:)), localized: false)
                presetItem.representedObject = preset
                menu.addItem(presetItem)
            }
        case .running:
            menu.addItem(item("pause", symbol: "pause.fill", action: #selector(pause)))
            menu.addItem(item("reset", symbol: "arrow.clockwise", action: #selector(reset)))
        case .paused:
            menu.addItem(item("resume", symbol: "play.fill", action: #selector(resume)))
            menu.addItem(item("reset", symbol: "arrow.clockwise", action: #selector(reset)))
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: NSLocalizedString("quit", comment: ""), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func item(_ title: String, symbol: String, action: Selector, localized: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: localized ? NSLocalizedString(title, comment: "") : title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func presetTitle(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes % 60 == 0 {
            return String(format: NSLocalizedString("duration_hours", comment: ""), minutes / 60)
        }
        return String(format: NSLocalizedString("duration_minutes", comment: ""), minutes)
    }

    @objc private func openMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - ACTIONS

    @objc private func start() {
        run(countdown: 0)
    }

    @objc private func startCountdown(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else { return }
        run(countdown: duration)
    }

    private func run(countdown duration: TimeInterval) {
        deferAction { [self] in
            countdown = duration
            accumulated = 0
            startTime = Date()
            state = .running
            startTimer()
            updateDisplay()
            saveState()
        }
    }

    @objc private func pause() {
        deferAction { [self] in
            stopTimer()
            accumulated = currentElapsed()
            startTime = nil
            state = .paused
            updateDisplay()
            saveState()
        }
    }

    @objc private func resume() {
        deferAction { [self] in
            startTime = Date()
            state = .running
            startTimer()
            updateDisplay()
            saveState()
        }
    }

    @objc private func reset() {
        deferAction { [self] in resetToStopped() }
    }

    @objc private func quit() {
        deferAction { NSApp.terminate(nil) }
    }

    private func resetToStopped() {
        stopTimer()
        accumulated = 0
        startTime = nil
        countdown = 0
        state = .stopped
        updateDisplay()
        saveState()
    }

    /// Lets the status menu finish closing before the title changes.
    private func deferAction(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: block)
    }

    // MARK: - TIMER

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        stopTimer()
        guard !displaysAsleep else { return }

        // Fire on whole-second boundaries of the elapsed time so the display flips exactly when the digit changes.
        let untilNextSecond = 1 - currentElapsed().truncatingRemainder(dividingBy: 1)
        let timer = Timer(fire: Date(timeIntervalSinceNow: untilNextSecond), interval: 1, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        timer.tolerance = 0.1
        // .common keeps ticking while the status menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func currentElapsed() -> TimeInterval {
        guard state == .running, let startTime else { return accumulated }
        return accumulated + Date().timeIntervalSince(startTime)
    }

    private func updateDisplay() {
        let seconds: Int
        if countdown > 0 {
            let remaining = countdown - currentElapsed()
            if remaining <= 0 {
                NSSound.beep()
                resetToStopped()
                return
            }
            seconds = Int(remaining.rounded(.up))
        } else {
            seconds = Int(currentElapsed())
        }

        let text = format(seconds)
        guard text != lastDisplayText else { return }
        lastDisplayText = text
        statusItem.button?.title = text
    }

    private func format(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds / 60) % 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
