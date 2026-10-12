//
//  XiangKeIntent.swift
//  响课（XiangKe）— App Intent 锁屏探针
//
//  目的（最小验证）：确认「App Intent 动作」能否在**锁屏状态**下被快捷指令自动化执行，
//  以及执行时能否访问 /var/mobile/Library/Preferences 下的系统文件。
//
//  为什么需要验证：iOS 锁屏时禁止「打开 URL / 打开 App」，所以 xiangke://apply 那条路
//  在锁屏时必定失败。App Intent 若 openAppWhenRun = false，系统会在**后台**拉起 App 进程
//  执行 perform()，不进入前台 —— 理论上锁屏可用。但「能执行」不等于「能干活」：
//  系统偏好文件受数据保护（Data Protection）限制，锁屏时可能读写失败。
//  这一层只能实测，推理不出来。
//
//  本文件是**纯 Swift、零依赖**（不引用任何 CAL* 模块），把引入 Swift 混编的风险压到最低。
//  探针结果写入 xiangke-probe.log，由 ObjC 侧的设置页读取显示。
//

import Foundation
import UIKit
import AppIntents

/// 探针日志文件名。ObjC 侧 CALSettingsViewController 读同一份。
let kXiangKeProbeFileName = "xiangke-probe.log"

/// 真正的目标文件 —— 闹钟数据就存在这里。锁屏时能不能碰它，是整个方案的成败关键。
private let kMobileTimerPlist = "/var/mobile/Library/Preferences/com.apple.mobiletimer.plist"

// MARK: - 探针逻辑

enum XiangKeProbe {

    /// 候选目录。与 App 主体同一套思路：挑第一个真正能写的。
    static var candidateDirs: [String] {
        var dirs: [String] = []
        if let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                          .userDomainMask,
                                                          true).first, !docs.isEmpty {
            dirs.append(docs)
        }
        dirs.append("/var/mobile/Documents")
        dirs.append("/var/mobile/Library/Preferences")
        dirs.append(NSTemporaryDirectory())
        return dirs
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    /// 往指定文件追加文本。返回是否成功。
    @discardableResult
    static func append(_ text: String, to path: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }

        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return false }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return true
            } catch {
                return false
            }
        }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// 跑一次探针：返回报告文本，同时落盘一份。
    static func run() async -> String {
        // 锁屏的直接判据：受保护数据是否可访问。
        // false 就意味着「设备处于锁屏且尚未解锁过」，即这次确实是在锁屏下跑的。
        let protectedDataAvailable: Bool = await MainActor.run {
            UIApplication.shared.isProtectedDataAvailable
        }

        var lines: [String] = []
        lines.append("[\(timestamp())]")
        lines.append("  设备锁屏：\(protectedDataAvailable ? "否" : "是")"
                     + "（isProtectedDataAvailable = \(protectedDataAvailable)）")

        // 关键测试：锁屏时能否访问闹钟数据文件
        lines.append("  " + describeTargetFile())

        let body = lines.joined(separator: "\n")

        // 找第一个能写的目录，把报告落盘
        var note = "失败：所有候选目录都不可写"
        for dir in candidateDirs where !dir.isEmpty {
            let path = (dir as NSString).appendingPathComponent(kXiangKeProbeFileName)
            if append(body + "\n  → 日志写入：成功（\(path)）\n\n", to: path) {
                note = "成功（\(path)）"
                break
            }
        }

        return body + "\n  → 日志写入：\(note)"
    }

    /// 描述目标文件是否可访问 —— 这是整个方案能否成立的关键
    private static func describeTargetFile() -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: kMobileTimerPlist) else {
            return "闹钟数据文件：不存在（\(kMobileTimerPlist)）"
        }

        let attr = try? fm.attributesOfItem(atPath: kMobileTimerPlist)
        let size = (attr?[.size] as? NSNumber)?.intValue ?? -1
        let protection = (attr?[.protectionKey] as? String) ?? "(未设置)"
        let readable = (fm.contents(atPath: kMobileTimerPlist)?.count ?? 0) > 0

        return "闹钟数据文件：存在  大小=\(size)  保护等级=\(protection)  可读=\(readable ? "是" : "否")"
    }
}

// MARK: - App Intent

/// 快捷指令里会出现的动作：响课锁屏探针
struct XiangKeProbeIntent: AppIntent {

    static var title: LocalizedStringResource = "响课锁屏探针"

    static var description: IntentDescription? = IntentDescription(
        "记录一次后台执行，用来验证锁屏状态下 App Intent 能否运行、能否访问系统文件。")

    /// 关键：false = 不进入前台，由系统在后台拉起 App 进程执行。
    /// 锁屏时禁止的是「把 App 拉到前台」，后台执行不受限。
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let report = await XiangKeProbe.run()
        NSLog("[响课·探针]\n%@", report)
        return .result()
    }
}
