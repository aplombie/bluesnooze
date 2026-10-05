//
//  AppDelegate.swift
//  Bluesnooze
//
//  Created by Oliver Peate on 07/04/2020.
//  Copyright © 2020 Oliver Peate. All rights reserved.
//

import Cocoa
import IOBluetooth
import LaunchAtLogin
import os

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let powerLog = Logger(subsystem: "Blueout", category: "BluetoothPower")
    private var powerRequestGeneration = 0

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        initStatusItem()
        setLaunchAtLoginState()
        setupNotificationHandlers()
        setBluetooth(powerOn: true, reason: "launch")
    }

    // MARK: Click handlers

    @IBAction func launchAtLoginClicked(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
        setLaunchAtLoginState()
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }

    // MARK: Notification handlers

    func setupNotificationHandlers() {
        [
            NSWorkspace.willSleepNotification: #selector(onPowerDown(note:)),
            NSWorkspace.willPowerOffNotification: #selector(onPowerDown(note:)),
            NSWorkspace.didWakeNotification: #selector(onPowerUp(note:))
        ].forEach { notification, sel in
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: sel, name: notification, object: nil)
        }
    }

    @objc func onPowerDown(note: NSNotification) {
        let reason = note.name == NSWorkspace.willSleepNotification ? "willSleep" : "willPowerOff"
        setBluetooth(powerOn: false, reason: reason)
    }

    @objc func onPowerUp(note: NSNotification) {
        setBluetooth(powerOn: true, reason: "didWake")
    }

    private func setBluetooth(powerOn: Bool, reason: String) {
        powerRequestGeneration += 1
        let generation = powerRequestGeneration
        let started = ProcessInfo.processInfo.systemUptime
        let before = IOBluetoothPreferenceGetControllerPowerState()
        powerLog.notice("event=\(reason, privacy: .public) request=\(generation) target=\(powerOn ? 1 : 0) before=\(before)")
        IOBluetoothPreferenceSetControllerPowerState(powerOn ? 1 : 0)

        // A returned setter call is not proof of a state change. These bounded,
        // read-only samples report the preference API's state, not accessory readiness.
        // A newer sleep/wake request invalidates samples from the previous request.
        for delay in [0.0, 0.25, 1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.powerRequestGeneration == generation else { return }
                let observed = IOBluetoothPreferenceGetControllerPowerState()
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                self.powerLog.notice("request=\(generation) elapsed=\(elapsed) target=\(powerOn ? 1 : 0) reported=\(observed)")
            }
        }
    }

    // MARK: UI state

    private func initStatusItem() {
        if UserDefaults.standard.bool(forKey: "hideIcon") {
            return
        }

        if let icon = NSImage(named: "bluesnooze") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "Bluesnooze"
        }
        statusItem.menu = statusMenu
    }

    private func setLaunchAtLoginState() {
        let state = LaunchAtLogin.isEnabled ? NSControl.StateValue.on : NSControl.StateValue.off
        launchAtLoginMenuItem.state = state
    }
}
