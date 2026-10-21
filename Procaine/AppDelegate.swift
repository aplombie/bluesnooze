//
//  AppDelegate.swift
//  Procaine
//
//  Created by Oliver Peate on 07/04/2020.
//  Copyright © 2020 Oliver Peate. All rights reserved.
//

import Cocoa
import CoreBluetooth
import ServiceManagement
import os

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaults = UserDefaults.standard
    private let powerLog = Logger(subsystem: "io.github.aplombie.procaine", category: "BluetoothPower")
    private let lifecycleLog = Logger(subsystem: "io.github.aplombie.procaine", category: "AppLifecycle")
    private lazy var automation = BluetoothAutomation(
        controller: BluetoothPowerController(), paused: true
    )
    private let logiService = LogiOptionsService()
    private let recoveryStore = LogiRecoveryStore()
    private lazy var logiAutomation = AppSleepAutomation(
        service: logiService, ownsStop: recoveryStore.ownsStop,
        saveOwnership: { [weak self] owned in self?.recoveryStore.save(owned) ?? false }
    )
    private let bluetoothActionItem = NSMenuItem(title: "Turn Bluetooth Off During Sleep", action: #selector(toggleBluetoothAction), keyEquivalent: "")
    private let logiActionItem = NSMenuItem(title: "Pause Logi Options+ During Sleep…", action: #selector(toggleLogiAction), keyEquivalent: "")
    private let logiStateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let restoreLogiItem = NSMenuItem(title: "Restore Logi Options+", action: #selector(restoreLogi), keyEquivalent: "")
    private var quitPending = false
    private var settingsWindow: NSWindow?
    private var settingsControls: [String: NSButton] = [:]
    private var settingsStatus: NSTextField?
    private let automationItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let powerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let transitionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Automation", action: #selector(togglePause), keyEquivalent: "p")
    private let restoreItem = NSMenuItem(title: "Restore Bluetooth", action: #selector(restoreBluetooth), keyEquivalent: "")
    private let loginSettingsItem = NSMenuItem(title: "Open Login Items Settings…", action: #selector(openLoginSettings), keyEquivalent: "")
    private let privacyItem = NSMenuItem(title: "Open Bluetooth Privacy Settings…", action: #selector(openPrivacySettings), keyEquivalent: "")
    private var conflictingAppIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            [PreferenceMigration.legacyDomain, "io.github.aplombie.procaine"].contains($0.bundleIdentifier ?? "")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PreferenceMigration.migrate(into: defaults, legacy: defaults.persistentDomain(forName: PreferenceMigration.legacyDomain))
        setupMenu()
        automation.onChange = { [weak self] in self?.updateMenu() }
        automation.onSample = { [weak self] target, observed, elapsed in
            self?.powerLog.notice("target=\(String(describing: target), privacy: .public) reported=\(String(describing: observed), privacy: .public) elapsed=\(elapsed)")
        }
        logiAutomation.onChange = { [weak self] in
            if let self = self {
                self.lifecycleLog.notice("Logi phase=\(String(describing: self.logiAutomation.phase), privacy: .public) ownsStop=\(self.logiAutomation.ownsStop)")
            }
            self?.updateMenu()
            DispatchQueue.main.async { self?.finishPendingQuit() }
        }
        setupNotifications()
        synchronizePause()
        logiAutomation.startRecovery()
        // Startup never changes Bluetooth or login registration; unfinished Logi recovery is handled above.
        if defaults.bool(forKey: "bluetoothSleepEnabled") { automation.refresh() }
        statusItem.isVisible = !defaults.bool(forKey: "hideIcon")
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let isLoginLaunch = launchEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
        if defaults.bool(forKey: "hideIcon") && !isLoginLaunch { showSettings() }
    }

    private func setupMenu() {
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        launchAtLoginMenuItem.keyEquivalent = "l"
        let quit = statusMenu.items.last!
        quit.title = "Quit Procaine"
        quit.keyEquivalent = "q"
        statusMenu.insertItem(automationItem, at: 0)
        statusMenu.insertItem(powerItem, at: 1)
        statusMenu.insertItem(transitionItem, at: 2)
        statusMenu.insertItem(.separator(), at: 3)
        statusMenu.insertItem(pauseItem, at: 4)
        statusMenu.insertItem(restoreItem, at: 5)
        let settings = NSMenuItem(title: "Open Bluetooth Settings…", action: #selector(openBluetoothSettings), keyEquivalent: "b")
        statusMenu.insertItem(settings, at: 6)
        statusMenu.insertItem(privacyItem, at: 7)
        statusMenu.insertItem(.separator(), at: 8)
        statusMenu.insertItem(bluetoothActionItem, at: 9)
        statusMenu.insertItem(logiActionItem, at: 10)
        statusMenu.insertItem(logiStateItem, at: 11)
        statusMenu.insertItem(restoreLogiItem, at: 12)
        statusMenu.insertItem(.separator(), at: 13)
        statusMenu.insertItem(loginSettingsItem, at: statusMenu.items.count - 1)
        let appSettings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        statusMenu.insertItem(appSettings, at: statusMenu.items.count - 1)
        let help = NSMenuItem(title: "About Procaine…", action: #selector(showAbout), keyEquivalent: "")
        statusMenu.insertItem(help, at: statusMenu.items.count - 1)
        for item in statusMenu.items { item.target = self }
        for item in [automationItem, powerItem, transitionItem, logiStateItem] { item.isEnabled = false }
        statusItem.menu = statusMenu
    }

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        // Retain the workspace wake trigger validated locally. No claim that it universally
        // excludes dark wakes; release verification must cover maintenance wakes explicitly.
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(applicationsChanged), name: name, object: nil)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        synchronizePause()
        if defaults.bool(forKey: "bluetoothSleepEnabled") { automation.refresh() }
    }

    @objc private func willSleep() {
        synchronizePause()
        automation.sleep()
        logiAutomation.sleep()
    }

    @objc private func didWake() {
        synchronizePause()
        automation.wake()
        logiAutomation.wake()
    }

    @objc private func applicationsChanged() { synchronizePause() }

    private func synchronizePause() {
        let paused = defaults.bool(forKey: "automationPaused") || conflictingAppIsRunning || quitPending
        automation.setPaused(paused || !defaults.bool(forKey: "bluetoothSleepEnabled"))
        logiAutomation.setPaused(paused || !defaults.bool(forKey: "logiSleepEnabled"))
        updateMenu()
    }

    private func updateMenu() {
        let conflict = conflictingAppIsRunning
        let radioEnabled = defaults.bool(forKey: "bluetoothSleepEnabled")
        let logiEnabled = defaults.bool(forKey: "logiSleepEnabled")
        // The mark reflects selected sleep actions, not the current radio state.
        // Temporary pauses and conflicts remain explicit in the status and tooltip.
        let iconName = radioEnabled || logiEnabled ? "procaine" : "procaine-off"
        let image = NSImage(named: iconName) ?? NSImage(
            systemSymbolName: "moon.zzz", accessibilityDescription: "Procaine")
        image?.isTemplate = true
        statusItem.button?.image = image
        automationItem.title = conflict ? "Automation paused — another copy is running" :
            (defaults.bool(forKey: "automationPaused") ? "Sleep protection paused" :
                (radioEnabled || logiEnabled ? "Sleep protection enabled" : "Choose your sleep actions below"))
        bluetoothActionItem.state = radioEnabled ? .on : .off
        logiActionItem.state = logiEnabled ? .on : .off
        bluetoothActionItem.isEnabled = !conflict
        logiActionItem.isEnabled = !conflict && (logiService.isInstalled || logiEnabled)
        logiActionItem.title = logiService.isInstalled ? "Pause Logi Options+ During Sleep…" : "Logi Options+ Not Available"
        logiStateItem.isHidden = !logiEnabled && !logiAutomation.ownsStop
        switch logiAutomation.phase {
        case .idle: logiStateItem.title = "Logi sleep action ready — experimental"
        case .checking: logiStateItem.title = "Checking Logi Options+…"
        case .stopping: logiStateItem.title = "Pausing Logi Options+…"
        case .stopped: logiStateItem.title = "Logi Options+ paused for sleep"
        case .restoring: logiStateItem.title = "Restoring Logi Options+…"
        case .stopFailed: logiStateItem.title = "Logi pause not confirmed"
        case .restoreFailed: logiStateItem.title = "Logi restoration not confirmed"
        case .unavailable: logiStateItem.title = "Logi sleep action unavailable"
        }
        restoreLogiItem.isHidden = !logiAutomation.canRestore
        switch automation.reportedPower {
        case .on: powerItem.title = "Bluetooth reported on"
        case .off: powerItem.title = "Bluetooth reported off"
        case .unknown: powerItem.title = "Bluetooth state unavailable"
        }
        if !radioEnabled { powerItem.title = "Bluetooth power left unchanged" }
        switch automation.transition {
        case .idle: transitionItem.isHidden = true
        case .pending: transitionItem.title = "Checking Bluetooth change…"; transitionItem.isHidden = false
        case .confirmed: transitionItem.title = "Power change reported by macOS"; transitionItem.isHidden = false
        case .unconfirmed: transitionItem.title = "Bluetooth change not confirmed"; transitionItem.isHidden = false
        }
        pauseItem.title = defaults.bool(forKey: "automationPaused") ? "Resume Automation" : "Pause Automation"
        pauseItem.isEnabled = !conflict
        restoreItem.isHidden = !automation.canRestore
        privacyItem.isHidden = !radioEnabled || (CBManager.authorization != .denied && CBManager.authorization != .restricted)
        let service = SMAppService.mainApp
        launchAtLoginMenuItem.state = service.status == .enabled ? .on : .off
        launchAtLoginMenuItem.title = service.status == .requiresApproval ? "Launch at Login — Approval Needed" : "Launch at Login"
        loginSettingsItem.isHidden = service.status != .requiresApproval && service.status != .notFound
        statusItem.button?.toolTip = "Procaine — \(automationItem.title)"
        statusItem.button?.setAccessibilityLabel("Procaine — \(automationItem.title)")
        updateSettings()
    }


    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 450),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Procaine Settings"
            window.isReleasedWhenClosed = false
            window.center()
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
            ])
            let title = NSTextField(labelWithString: "Procaine")
            title.font = .systemFont(ofSize: 22, weight: .semibold)
            stack.addArrangedSubview(title)
            func checkbox(_ title: String, key: String, action: Selector) {
                let button = NSButton(checkboxWithTitle: title, target: self, action: action)
                settingsControls[key] = button
                stack.addArrangedSubview(button)
            }
            checkbox("Turn Bluetooth off during sleep", key: "bluetooth", action: #selector(toggleBluetoothAction))
            checkbox("Pause Logi Options+ during sleep", key: "logi", action: #selector(toggleLogiAction))
            checkbox("Pause automation", key: "pause", action: #selector(togglePause))
            checkbox("Launch at login", key: "login", action: #selector(settingsLoginClicked))
            checkbox("Show menu bar icon", key: "icon", action: #selector(toggleMenuBarIcon))
            let hint = NSTextField(wrappingLabelWithString: "When the icon is hidden, open Procaine from Applications or Spotlight to return to Settings.")
            hint.textColor = .secondaryLabelColor
            hint.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(hint)
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let status = NSTextField(wrappingLabelWithString: "")
            settingsStatus = status
            stack.addArrangedSubview(status)
            status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let recovery = NSStackView()
            recovery.orientation = .horizontal
            recovery.spacing = 12
            for (title, key, action) in [("Restore Bluetooth", "restoreBluetooth", #selector(restoreBluetooth)),
                                         ("Restore Logi Options+", "restoreLogi", #selector(restoreLogi))] {
                let button = NSButton(title: title, target: self, action: action)
                settingsControls[key] = button
                recovery.addArrangedSubview(button)
            }
            stack.addArrangedSubview(recovery)
            let footer = NSStackView()
            footer.orientation = .horizontal
            footer.spacing = 12
            footer.addArrangedSubview(NSButton(title: "Login Items Settings…", target: self, action: #selector(openLoginSettings)))
            footer.addArrangedSubview(NSButton(title: "Quit Procaine", target: self, action: #selector(quitClicked)))
            stack.addArrangedSubview(footer)
            settingsWindow = window
        }
        synchronizePause()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func updateSettings() {
        guard settingsWindow != nil else { return }
        settingsControls["bluetooth"]?.state = bluetoothActionItem.state
        settingsControls["bluetooth"]?.isEnabled = bluetoothActionItem.isEnabled
        settingsControls["logi"]?.state = logiActionItem.state
        settingsControls["logi"]?.isEnabled = logiActionItem.isEnabled
        settingsControls["pause"]?.state = defaults.bool(forKey: "automationPaused") ? .on : .off
        settingsControls["pause"]?.isEnabled = pauseItem.isEnabled
        settingsControls["login"]?.state = launchAtLoginMenuItem.state
        settingsControls["login"]?.title = launchAtLoginMenuItem.title
        settingsControls["icon"]?.state = defaults.bool(forKey: "hideIcon") ? .off : .on
        settingsControls["restoreBluetooth"]?.isEnabled = automation.canRestore
        settingsControls["restoreLogi"]?.isEnabled = logiAutomation.canRestore
        settingsStatus?.stringValue = [automationItem.title, powerItem.title,
            logiStateItem.isHidden ? nil : logiStateItem.title,
            transitionItem.isHidden ? nil : transitionItem.title].compactMap { $0 }.joined(separator: "\n")
    }

    @objc private func settingsLoginClicked() { launchAtLoginClicked(launchAtLoginMenuItem) }

    @objc private func toggleMenuBarIcon() {
        defaults.set(!defaults.bool(forKey: "hideIcon"), forKey: "hideIcon")
        statusItem.isVisible = !defaults.bool(forKey: "hideIcon")
        updateSettings()
    }

    @objc private func togglePause() {
        defaults.set(!defaults.bool(forKey: "automationPaused"), forKey: "automationPaused")
        synchronizePause()
    }

    @objc private func toggleBluetoothAction() {
        defaults.set(!defaults.bool(forKey: "bluetoothSleepEnabled"), forKey: "bluetoothSleepEnabled")
        synchronizePause()
        if defaults.bool(forKey: "bluetoothSleepEnabled") { automation.refresh() }
    }

    @objc private func toggleLogiAction() {
        if !defaults.bool(forKey: "logiSleepEnabled") {
            let alert = NSAlert()
            alert.messageText = "Pause Logi Options+ during sleep?"
            alert.informativeText = "This experimental action temporarily stops the Options+ background service and restores it on wake. Bluetooth stays on unless you also enable its separate sleep action.\n\nIf restoration fails, use Restore Logi Options+. If Procaine closes unexpectedly, reopen it to recover your custom controls. This has not yet been verified to resolve sleep drain or preserve Watch unlock."
            alert.addButton(withTitle: "Enable Logi Sleep Action")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        defaults.set(!defaults.bool(forKey: "logiSleepEnabled"), forKey: "logiSleepEnabled")
        synchronizePause()
    }

    @objc private func restoreLogi() { logiAutomation.restoreManually() }

    @objc private func restoreBluetooth() {
        synchronizePause()
        automation.restoreManually()
    }

    @IBAction func launchAtLoginClicked(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .notRegistered: try service.register()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            case .notFound: showMessage("Launch at login unavailable", "Move Procaine to Applications, then try again.")
            @unknown default: showMessage("Launch at login unavailable", "Open Login Items in System Settings to check Procaine’s registration.")
            }
        } catch {
            showMessage("Launch at login could not be changed", "Check Procaine in System Settings → General → Login Items. macOS may require your approval.")
        }
        updateMenu()
    }

    @objc private func openBluetoothSettings() {
        openSettings("x-apple.systempreferences:com.apple.BluetoothSettings")
    }

    @objc private func openPrivacySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func openSettings(_ address: String) {
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else {
            showMessage("Open System Settings", "Open System Settings manually to adjust Bluetooth or login access.")
            return
        }
    }

    @objc private func showAbout() {
        showMessage("Procaine", "Choose independent sleep actions for Bluetooth and Logi Options+. Pause Automation suspends both.\n\nBluetooth sleep control restores only a shutdown initiated by Procaine and can interfere with Apple Watch unlock.\n\nThe experimental Logi action leaves Bluetooth on, stops only the supported Options+ service, and restores it on wake. Its sleep benefits, custom controls, and Watch unlock still need validation.\n\nA maintenance fork of Bluesnooze by Oliver Peate, licensed under MIT.")
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard logiAutomation.ownsStop || logiAutomation.isBusy else { return .terminateNow }
        quitPending = true
        logiAutomation.setPaused(true)
        logiAutomation.wake()
        logiAutomation.restoreManually()
        DispatchQueue.main.async { [weak self] in self?.finishPendingQuit() }
        return .terminateLater
    }

    private func finishPendingQuit() {
        guard quitPending && !logiAutomation.isBusy else { return }
        quitPending = false
        if logiAutomation.ownsStop {
            let alert = NSAlert()
            alert.messageText = "Logi Options+ has not been restored"
            alert.informativeText = "Keep Procaine open to try Restore Logi Options+, or quit and reopen Procaine to recover later. Custom controls may be unavailable until restoration succeeds."
            alert.addButton(withTitle: "Keep Procaine Open")
            alert.addButton(withTitle: "Quit Anyway")
            let quit = alert.runModal() == .alertSecondButtonReturn
            NSApplication.shared.reply(toApplicationShouldTerminate: quit)
            if !quit { synchronizePause() }
        } else {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}
