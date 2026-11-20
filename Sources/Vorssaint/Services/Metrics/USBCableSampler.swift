// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

struct USBCableReading: Equatable, Sendable {
    /// USB-PD Discover Identity data reported by the cable itself.
    let advertisedRate: ClosedRange<Int>?
    let advertisedAmps: Int?
    let advertisedWatts: Int?

    static func decode(_ objects: [Data]) -> Self? {
        guard objects.count >= 4, objects[0].count == 4, objects[3].count == 4 else { return nil }
        let header = word(objects[0])
        let cable = word(objects[3])
        let productType = (header >> 27) & 7
        guard productType == 3 || productType == 4, cable != 0 else { return nil }
        let rate: ClosedRange<Int>?
        switch cable & 7 {
        case 0: rate = 480...480
        case 1: rate = 5_000...5_000
        case 2: rate = 10_000...10_000
        // The same code means 20 or 40 Gb/s depending on the specification revision.
        case 3: rate = 20_000...40_000
        case 4: rate = 80_000...80_000
        default: rate = nil
        }
        let amps: Int?
        switch (cable >> 5) & 3 {
        case 1: amps = 3
        case 2: amps = 5
        default: amps = nil
        }
        let carriesPower = productType == 3 || (cable & (1 << 4)) != 0
        let epr = (cable & (1 << 17)) != 0
        let voltageRating = (cable >> 9) & 3
        // A 50 V insulation rating is not a 50 V power contract. Only
        // explicitly compatible 5 A EPR cables qualify for the 48 V ceiling.
        let watts = carriesPower ? amps.map { $0 * (epr && voltageRating == 3 && $0 == 5 ? 48 : 20) } : nil
        return Self(advertisedRate: rate, advertisedAmps: carriesPower ? amps : nil, advertisedWatts: watts)
    }

    private static func word(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
}

struct USBPortReading: Identifiable, Equatable, Sendable {
    let portNumber: Int
    var cable: USBCableReading?
    var negotiatedUSBRate: Int?
    var selectedPowerWatts: Double?
    var thunderboltPresent = false
    var id: Int { portNumber }
}

/// Read-only observations. No USB user clients, device probes or raw registry
/// dumps are needed. The system monitor calls this on its sampling queue.
enum USBCableSampler {
    static func sample() -> [USBPortReading] {
        var ports: [Int: USBPortReading] = [:]
        func collect(_ className: String, _ update: (io_service_t, inout USBPortReading) -> Void) {
            guard let matching = IOServiceMatching(className) else { return }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let number = portNumber(service), property(service, "Active") as? Bool != false else { continue }
                var port = ports[number] ?? USBPortReading(portNumber: number)
                update(service, &port)
                if port.cable != nil || port.negotiatedUSBRate != nil
                    || port.selectedPowerWatts != nil || port.thunderboltPresent {
                    ports[number] = port
                }
            }
        }
        // Prefer the near-end e-marker. A bare cable can instead publish its
        // identity as the partner, which still must declare a cable product type.
        for className in ["IOPortTransportComponentCCUSBPDSOPp", "IOPortTransportComponentCCUSBPDSOP"] {
            collect(className) { service, port in
                guard port.cable == nil,
                      let metadata = property(service, "Metadata") as? [String: Any],
                      let words = metadata["VDOs"] as? [Data] else { return }
                port.cable = USBCableReading.decode(words)
            }
        }
        collect("IOPortTransportStateUSB3") { service, port in
            guard property(service, "Active") as? Bool == true,
                  property(service, "Tunneled") as? Bool != true,
                  property(service, "TRM_TransportRestricted") as? Bool != true else { return }
            switch property(service, "SuperSpeedSignaling") as? Int {
            case 1: port.negotiatedUSBRate = max(port.negotiatedUSBRate ?? 0, 5_000)
            case 2: port.negotiatedUSBRate = max(port.negotiatedUSBRate ?? 0, 10_000)
            default: break
            }
        }
        collect("IOPortTransportStateCIO") { service, port in
            port.thunderboltPresent = port.thunderboltPresent || property(service, "Active") as? Bool == true
        }
        collect("IOPortFeaturePowerSource") { service, port in
            guard let option = property(service, "WinningPowerSourceOption") as? [String: Any],
                  option["Class"] as? String == "IOPortFeaturePowerSourceOptionFixed",
                  let millivolts = option["Voltage (mV)"] as? Int, (1...48_000).contains(millivolts),
                  let milliamps = option["Max Current (mA)"] as? Int, (1...5_000).contains(milliamps) else { return }
            port.selectedPowerWatts = Double(millivolts) * Double(milliamps) / 1_000_000
        }
        return ports.values.sorted { $0.portNumber < $1.portNumber }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func portNumber(_ service: io_service_t) -> Int? {
        let type = property(service, "ParentBuiltInPortType") as? Int
            ?? property(service, "ParentPortType") as? Int
        let number = property(service, "ParentBuiltInPortNumber") as? Int
            ?? property(service, "ParentPortNumber") as? Int
        guard type == 2, let number, (0..<256).contains(number) else { return nil }
        return number
    }
}
