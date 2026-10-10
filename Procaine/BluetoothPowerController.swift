import CoreBluetooth
import IOBluetooth

/// Private controller preferences are confined here so policy tests never touch hardware.
final class BluetoothPowerController: BluetoothPowerControlling {
    func readPower() -> BluetoothPower {
        guard CBManager.authorization != .denied && CBManager.authorization != .restricted else { return .unknown }
        switch IOBluetoothPreferenceGetControllerPowerState() {
        case 0: return .off
        case 1: return .on
        default: return .unknown
        }
    }

    func requestPower(_ state: BluetoothPower) {
        guard CBManager.authorization != .denied && CBManager.authorization != .restricted else { return }
        switch state {
        case .on: IOBluetoothPreferenceSetControllerPowerState(1)
        case .off: IOBluetoothPreferenceSetControllerPowerState(0)
        case .unknown: break
        }
    }
}
