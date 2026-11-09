import Foundation

public enum LoginSession {
    /// 現在のユーザーのコンソールログイン時刻(utmpx。`last` と同じ記録)。
    /// 再ログインでは WindowServer は再起動しない(pid が変わらないことを実測)ので、その起動時刻は使えない。
    public static func consoleLoginTime() -> Date? {
        let user = NSUserName()
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            var e = entry.pointee
            guard e.ut_type == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: &e.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let name = withUnsafeBytes(of: &e.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard line == "console", name == user else { continue }
            let t = Date(timeIntervalSince1970: TimeInterval(e.ut_tv.tv_sec) + TimeInterval(e.ut_tv.tv_usec) / 1e6)
            if latest.map({ t > $0 }) ?? true { latest = t }
        }
        return latest
    }
}
