import SwiftUI
import ServiceManagement
import OSLog

class ZaiUsageStore: ObservableObject {
    @Published var percentage: Double = 0
    @Published var currentTokens: Int = 0
    @Published var limitTokens: Int = 800_000_000
    @Published var resetTime: String?
    @Published var status: String = "初始化中..."
    @Published var lastUpdated: String = ""
    @Published var isConnected: Bool = false
    @Published var sevenDayPrompts: Int = 0
    @Published var sevenDayTokens: Int = 0
    @Published var thirtyDayPrompts: Int = 0
    @Published var thirtyDayTokens: Int = 0

    private var apiKey: String?
    private var timer: Timer?
    private let configPath: String

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectDir = NSString(string: homeDir).appendingPathComponent("Downloads/zai-usage-tracker")
        self.configPath = NSString(string: projectDir).appendingPathComponent(".zai_apikey.json")
        loadApiKey()
        startTimer()
        fetchUsage()
    }

    deinit {
        timer?.invalidate()
    }

    private func loadApiKey() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["apiKey"] as? String else {
            status = "未配置 API Key"
            return
        }
        apiKey = key
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchUsage()
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func fetchUsage() {
        os_log("fetchUsage() called")
        guard let apiKey = apiKey else {
            DispatchQueue.main.async {
                self.status = "未配置 API Key"
            }
            return
        }

        os_log("API key loaded, starting requests")
        DispatchQueue.main.async {
            self.status = "查询中..."
        }

        let now = Date()
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let start7d = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        let start30d = cal.date(byAdding: .month, value: -1, to: cal.startOfDay(for: now))!

        let baseUrl = "https://api.z.ai"
        let endStr = formatDateTime(endOfDay)
        let start7dStr = formatDateTime(start7d)
        let start30dStr = formatDateTime(start30d)

        let qp7d = "?startTime=\(start7dStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&endTime=\(endStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
        let qp30d = "?startTime=\(start30dStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&endTime=\(endStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"

        let urls = [
            "\(baseUrl)/api/monitor/usage/quota/limit",
            "\(baseUrl)/api/monitor/usage/model-usage\(qp7d)",
            "\(baseUrl)/api/monitor/usage/model-usage\(qp30d)"
        ]

        let dispatchGroup = DispatchGroup()
        var quotaResult: [String: Any]?
        var usage7dResult: [String: Any]?
        var usage30dResult: [String: Any]?

        for (i, urlString) in urls.enumerated() {
            guard let url = URL(string: urlString) else { continue }
            dispatchGroup.enter()

            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer { dispatchGroup.leave() }

                guard let data = data, let httpResponse = response as? HTTPURLResponse else { return }

                if httpResponse.statusCode == 401 {
                    var retryRequest = request
                    retryRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    let retryTask = URLSession.shared.dataTask(with: retryRequest) { retryData, retryResponse, _ in
                        defer { dispatchGroup.leave() }
                        guard let retryData = retryData,
                              let retryJson = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any] else { return }
                        if i == 0 { quotaResult = retryJson }
                        else if i == 1 { usage7dResult = retryJson }
                        else { usage30dResult = retryJson }
                    }
                    dispatchGroup.enter()
                    retryTask.resume()
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                if let wrapper = json["data"] as? [String: Any] {
                    if i == 0 { quotaResult = wrapper }
                    else if i == 1 { usage7dResult = wrapper }
                    else { usage30dResult = wrapper }
                } else {
                    if i == 0 { quotaResult = json }
                    else if i == 1 { usage7dResult = json }
                    else { usage30dResult = json }
                }
            }
            task.resume()
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            os_log("All requests completed")

            var newPercentage: Double = 0
            var newCurrent: Int = 0
            var newLimit: Int = 800_000_000
            var newReset: String?
            var new7dPrompts: Int = 0
            var new7dTokens: Int = 0
            var new30dPrompts: Int = 0
            var new30dTokens: Int = 0

            if let quota = quotaResult,
               let limits = quota["limits"] as? [[String: Any]] {
                for limit in limits {
                    if limit["type"] as? String == "TOKENS_LIMIT" {
                        newPercentage = limit["percentage"] as? Double ?? 0
                        if let cv = limit["currentValue"] as? Int { newCurrent = cv }
                        if let u = limit["usage"] as? Int { newLimit = u }
                        if let rt = limit["nextResetTime"] as? Double {
                            let date = Date(timeIntervalSince1970: rt / 1000.0)
                            let formatter = DateFormatter()
                            formatter.dateFormat = "HH:mm"
                            newReset = formatter.string(from: date)
                        } else if let rt = limit["nextResetTime"] as? Int {
                            let date = Date(timeIntervalSince1970: Double(rt) / 1000.0)
                            let formatter = DateFormatter()
                            formatter.dateFormat = "HH:mm"
                            newReset = formatter.string(from: date)
                        }
                        if newCurrent == 0 && newPercentage > 0 {
                            newCurrent = Int(Double(newLimit) * newPercentage / 100)
                        }
                    }
                }
            }

            if let u7d = usage7dResult,
               let total7d = u7d["totalUsage"] as? [String: Any] {
                new7dPrompts = total7d["totalModelCallCount"] as? Int ?? 0
                new7dTokens = total7d["totalTokensUsage"] as? Int ?? 0
            }

            if let u30d = usage30dResult,
               let total30d = u30d["totalUsage"] as? [String: Any] {
                new30dPrompts = total30d["totalModelCallCount"] as? Int ?? 0
                new30dTokens = total30d["totalTokensUsage"] as? Int ?? 0
            }

            self.percentage = newPercentage
            self.currentTokens = newCurrent
            self.limitTokens = newLimit
            self.sevenDayPrompts = new7dPrompts
            self.sevenDayTokens = new7dTokens
            self.thirtyDayPrompts = new30dPrompts
            self.thirtyDayTokens = new30dTokens
            self.isConnected = true
            self.status = "已连接"

            self.resetTime = newReset

            let nowFormatter = DateFormatter()
            nowFormatter.dateFormat = "HH:mm:ss"
            self.lastUpdated = nowFormatter.string(from: Date())
        }
    }

    func refresh() {
        fetchUsage()
    }
}

struct MenuBarView: View {
    @ObservedObject var store: ZaiUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Z.ai GLM 用量")
                .font(.headline)

            Divider()

            HStack {
                Text("5小时窗口")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if store.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Text("用量:")
                Text("\(formatNumber(store.currentTokens)) / \(formatNumber(store.limitTokens))")
                    .monospacedDigit()
            }
            .font(.system(.body, design: .monospaced))

            HStack {
                Text("使用率:")
                Text(String(format: "%.2f%%", store.percentage))
                    .foregroundColor(store.percentage > 80 ? .red : store.percentage > 50 ? .orange : .green)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            if let reset = store.resetTime {
                HStack {
                    Text("重置:")
                    Text(reset)
                        .monospacedDigit()
                }
            }

            Divider()

            Text("7天统计")
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                Text("请求:")
                Text(formatNumber(store.sevenDayPrompts))
                    .monospacedDigit()
            }
            HStack {
                Text("Token:")
                Text(formatNumber(store.sevenDayTokens))
                    .monospacedDigit()
            }

            Divider()

            Text("30天统计")
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                Text("请求:")
                Text(formatNumber(store.thirtyDayPrompts))
                    .monospacedDigit()
            }
            HStack {
                Text("Token:")
                Text(formatNumber(store.thirtyDayTokens))
                    .monospacedDigit()
            }

            Divider()

            HStack {
                Text("更新:")
                Text(store.lastUpdated.isEmpty ? "--:--:--" : store.lastUpdated)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Divider()

            Button("立即刷新") {
                store.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000_000 { return String(format: "%.2fB", Double(num) / 1_000_000_000) }
        if num >= 1_000_000 { return String(format: "%.2fM", Double(num) / 1_000_000) }
        if num >= 1_000 { return String(format: "%.2fK", Double(num) / 1_000) }
        return "\(num)"
    }
}

@main
struct ZaiMenuBarApp: App {
    @StateObject private var store = ZaiUsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            let title: String = {
                if !store.isConnected { return "···" }
                if let reset = store.resetTime {
                    return "\(String(format: "%.1f%%", store.percentage)) | \(reset)"
                }
                return String(format: "%.1f%%", store.percentage)
            }()
            Text(title)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(store.percentage > 80 ? .red : store.percentage > 50 ? .orange : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}
