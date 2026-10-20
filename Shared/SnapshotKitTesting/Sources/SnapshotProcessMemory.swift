import Darwin

/// Process-wide memory in bytes. Peaks cover the host's lifetime, not one capture.
@_spi(Testing) public struct SnapshotProcessMemory: Codable, Sendable {
    public let residentBytes: UInt64
    public let peakResidentBytes: UInt64
    public let footprintBytes: UInt64
    public let peakFootprintBytes: Int64

    public static func current() throws -> Self {
        var info = task_vm_info_data_t()
        let capacity = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw ReadError.taskInfo(status) }
        // Require the last field we consume. Older kernels must not look like zero usage.
        let requiredBytes = MemoryLayout<task_vm_info_data_t>
            .offset(of: \.ledger_phys_footprint_peak)!
            + MemoryLayout<Int64>.size
        guard Int(count) * MemoryLayout<integer_t>.size >= requiredBytes else {
            throw ReadError.incompleteInfo(count)
        }
        return Self(
            residentBytes: info.resident_size,
            peakResidentBytes: info.resident_size_peak,
            footprintBytes: info.phys_footprint,
            peakFootprintBytes: info.ledger_phys_footprint_peak,
        )
    }

    private enum ReadError: Error {
        case taskInfo(kern_return_t)
        case incompleteInfo(mach_msg_type_number_t)
    }
}
