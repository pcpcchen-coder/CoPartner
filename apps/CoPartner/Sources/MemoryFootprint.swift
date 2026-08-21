import Darwin
// 🔒 真機膠水：跟 mach 要這個程序的實體足跡。CI 只保證編譯。
//
// 用 `phys_footprint` 而不是 `resident_size`：前者才是 Activity Monitor
// 「記憶體」欄顯示、以及系統決定要不要跳記憶體告警／終止程序時看的那個數字。
// 拿 `resident_size` 去追一個「跳告警」的問題，量的會是另一件事。
enum MemoryFootprint {

    /// 目前實體足跡（MB）。問不到回 nil——**不可以回 0**，
    /// 那會在曲線上畫出一段假的「記憶體歸零」。
    static func currentMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1024 / 1024
    }
}
