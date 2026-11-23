// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

struct USBCableReading: Equatable, Sendable {
    /// USB-PD Discover Identity data reported by the cable itself.
    let advertisedRate: ClosedRange<Int>?
    let advertisedAmps: Int?
    let advertisedWatts: Int?
    let activeCable: Bool
    let vendorID: UInt16?
    let productID: UInt16?
    let certificationID: UInt32?

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
        let vendor = UInt16(truncatingIfNeeded: header)
        let product = objects[2].count == 4 ? UInt16(truncatingIfNeeded: word(objects[2]) >> 16) : 0
        let certificate = objects[1].count == 4 ? word(objects[1]) : 0
        return Self(advertisedRate: rate, advertisedAmps: carriesPower ? amps : nil, advertisedWatts: watts,
                    activeCable: productType == 4, vendorID: vendor == 0 ? nil : vendor,
                    productID: product == 0 ? nil : product,
                    certificationID: certificate == 0 ? nil : certificate)
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
    var selectedMillivolts: Int?
    var selectedMilliamps: Int?
    var thunderboltPresent = false
    var id: Int { portNumber }
}

struct ThunderboltRouterReading: Identifiable, Equatable, Sendable {
    let id: UInt64
    let parent: UInt64?
    let name: String?
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
            port.selectedMillivolts = millivolts
            port.selectedMilliamps = milliamps
            port.selectedPowerWatts = Double(millivolts) * Double(milliamps) / 1_000_000
        }
        return ports.values.sorted { $0.portNumber < $1.portNumber }
    }

    static func thunderboltRouters() -> [ThunderboltRouterReading] {
        var result: [UInt64: ThunderboltRouterReading] = [:]
        for className in ["IOThunderboltSwitch", "IOIOThunderboltSwitch"] {
            guard let matching = IOServiceMatching(className) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while result.count < 128, case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let id = registryID(service), result[id] == nil else { continue }
                let name = (property(service, "Device Model Name") as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                result[id] = ThunderboltRouterReading(id: id, parent: routerParent(service),
                                                      name: name.flatMap { $0.isEmpty ? nil : String($0.prefix(160)) })
            }
        }
        // Host controllers without downstream devices do not form an active chain.
        let activeParents = Set(result.values.compactMap(\.parent))
        return result.values.filter { $0.parent != nil || activeParents.contains($0.id) }.sorted { $0.id < $1.id }
    }

    private static func routerParent(_ entry: io_registry_entry_t) -> UInt64? {
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<32 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
            if IOObjectConformsTo(current, "IOThunderboltSwitch") != 0 || IOObjectConformsTo(current, "IOIOThunderboltSwitch") != 0 {
                return registryID(current)
            }
        }
        return nil
    }

    private static func registryID(_ entry: io_registry_entry_t) -> UInt64? {
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS ? id : nil
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
