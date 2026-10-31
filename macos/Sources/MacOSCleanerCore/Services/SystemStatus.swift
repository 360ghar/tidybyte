import Darwin
import Foundation

/// Memory figures as Activity Monitor shows them. Read-only: Tidybyte never
/// "frees" memory, because macOS manages it better than any app can.
public struct MemorySnapshot: Sendable, Equatable {
    public enum Pressure: Sendable { case normal, warning, critical }

    public var totalBytes: Int64
    public var appBytes: Int64
    public var wiredBytes: Int64
    public var compressedBytes: Int64
    public var cachedBytes: Int64
    public var swapUsedBytes: Int64
    public var pressure: Pressure

    public var usedBytes: Int64 { appBytes + wiredBytes + compressedBytes }
}

public enum SystemStatus {
    public static func memory() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return snapshot(
            stats, pageSize: Int64(getpagesize()), totalBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            swapUsedBytes: swapUsed(), pressureLevel: sysctlInt("kern.memorystatus_vm_pressure_level"))
    }

    /// Activity Monitor's arithmetic: app memory is anonymous pages minus
    /// purgeable ones; cached files are file-backed pages.
    static func snapshot(
        _ stats: vm_statistics64, pageSize: Int64, totalBytes: Int64, swapUsedBytes: Int64, pressureLevel: Int?
    ) -> MemorySnapshot {
        let pages = { (value: UInt32) in Int64(value) * pageSize }
        let pressure: MemorySnapshot.Pressure = switch pressureLevel {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
        return MemorySnapshot(
            totalBytes: totalBytes,
            appBytes: max(0, pages(stats.internal_page_count) - pages(stats.purgeable_count)),
            wiredBytes: pages(stats.wire_count),
            compressedBytes: pages(stats.compressor_page_count),
            cachedBytes: pages(stats.external_page_count) + pages(stats.purgeable_count),
            swapUsedBytes: swapUsedBytes,
            pressure: pressure)
    }

    private static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }
}
