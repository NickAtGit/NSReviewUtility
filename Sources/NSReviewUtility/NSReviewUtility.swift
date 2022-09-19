
import StoreKit

@available(iOS 14.0, *)
public class NSReviewUtility: ObservableObject {

    @Published public private(set) var canAskForReview = false
    
    public var happinessIndexCheckCount = 5 { didSet { evaluateCanAskForReview() } }
    public var daysAfterFirstLaunchCheckCount = 3 { didSet { evaluateCanAskForReview() } }

    private var isDateDaysAfterFirstLaunchCheckCount: Bool {
        if let firstLaunchDate = firstLaunchDate {
            let thresholdDate = firstLaunchDate.addingTimeInterval(TimeInterval(daysAfterFirstLaunchCheckCount * 60 * 60 * 24))
            return Date() > thresholdDate
        } else {
            return false
        }
    }
    
    private var currentVersion = Bundle.main.releaseVersionNumber + "-" + Bundle.main.buildVersionNumber
    private var didAskForReviewInThisVersion: Bool { versionLastAskedForReview == currentVersion }
    private weak var loggingAdapter: ReviewUtilityLoggable?
       
    public init() {}
    
    public func start() {
        if let firstLaunchDate = firstLaunchDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            loggingAdapter?.log("⭐️ ReviewUtility started. First launched at \(formatter.string(from: firstLaunchDate)), happinessIndexCheckCount: \(happinessIndexCheckCount), daysAfterFirstLaunchCheckCount: \(daysAfterFirstLaunchCheckCount)")
        } else {
            firstLaunchDate = Date()
            loggingAdapter?.log("⭐️ ReviewUtility started for the first time. Setting first launched date to now.")
        }
        
        evaluateCanAskForReview()
    }
    
    public func setLoggingAdapter(_ loggingAdapter: ReviewUtilityLoggable) {
        self.loggingAdapter = loggingAdapter
    }
    
    private func evaluateCanAskForReview() {
        DispatchQueue.main.async {
            let askedForReviewThisYearCount = self.datesAskedForReview.filter { Calendar.current.isDateInThisYear($0) }.count
            let hasLessThanThreeReviewAttemptsThisYear = askedForReviewThisYearCount <= 3
            var logString = "⭐️ ReviewUtility asked \(askedForReviewThisYearCount) times this year for a review."
            
            // max(1, happinessIndexCheckCount) prevents division by zero
            let isUserHappy = self.happinessIndex != 0 && (self.happinessIndex % max(1, self.happinessIndexCheckCount) == 0)
            
            if self.didAskForReviewInThisVersion {
                logString += " Asked for review at version: \(self.versionLastAskedForReview), current version is: \(Bundle.main.releaseVersionNumber)."
                self.canAskForReview = false
            } else {
                logString += " currentDate > thresholdDate: \(self.isDateDaysAfterFirstLaunchCheckCount)."
                self.canAskForReview = self.isDateDaysAfterFirstLaunchCheckCount && hasLessThanThreeReviewAttemptsThisYear && isUserHappy
            }
            logString += " Can ask for review: \(self.canAskForReview)"
            self.loggingAdapter?.log(logString)
        }
    }
    
    public func incrementHappiness() {
        happinessIndex += 1
        loggingAdapter?.log("⭐️ Incremeting happiness, index is now: \(happinessIndex)")
        evaluateCanAskForReview()
    }
    
    public func decrementHappiness() {
        if happinessIndex > 0 {
            happinessIndex -= 1
            loggingAdapter?.log("⭐️ Decremeting happiness, index is now: \(happinessIndex)")
        } else {
            loggingAdapter?.log("⭐️ Can not decrement happiness because it is already \(happinessIndex)")
        }
    }
    
    public func resetHappiness() {
        happinessIndex = 0
        loggingAdapter?.log("⭐️ Resetting happiness, index is now: \(happinessIndex)")
    }
    
    public func askForReview(force: Bool = false) {
        let askForReviewClosure = { [weak self] in
            guard let self = self else { return }
            // Only save when in production
            if UIApplication.shared.isRunningInAppStoreEnvironment {
                self.recordAskForReview()
            }
            SKStoreReviewController.askForReview()
            self.loggingAdapter?.log("⭐️ Asked for review now")
        }
        
        if force && didAskForReviewInThisVersion {
            loggingAdapter?.log("⭐️ Can not force ask for review. Already asked for review in this version.")
        } else if force && !didAskForReviewInThisVersion {
            askForReviewClosure()
        } else if canAskForReview {
            askForReviewClosure()
        } else {
            loggingAdapter?.log("⭐️ Can not ask for review")
        }
    }
    
    public func recordAskForReview() {
        datesAskedForReview.append(Date())
        versionLastAskedForReview = currentVersion
        canAskForReview = false
        loggingAdapter?.log("⭐️ Recorded review request")
    }
    
    public func clearAllData() {
        datesAskedForReview = []
        firstLaunchDate = Date()
        happinessIndex = 0
        versionLastAskedForReview = "not asked yet"
        loggingAdapter?.log("⭐️ Clearing all data")
    }
}

@available(iOS 14.0, *)
extension NSReviewUtility {
    
    public private(set) var datesAskedForReview: [Date] {
        get {
            UserDefaults.standard.value(forKey: "datesAskedForReview") as? [Date] ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "datesAskedForReview")
        }
    }
    
    public private(set) var firstLaunchDate: Date? {
        get {
            UserDefaults.standard.value(forKey: "firstLaunchDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "firstLaunchDate")
        }
    }
        
    public private(set) var happinessIndex: Int {
        get {
            UserDefaults.standard.integer(forKey: "happinessIndex")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "happinessIndex")
        }
    }
    
    public private(set) var versionLastAskedForReview: String {
        get {
            UserDefaults.standard.string(forKey: "versionLastAskedForReview") ?? "not asked yet"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "versionLastAskedForReview")
        }
    }
}

@available(iOS 14.0, *)
extension SKStoreReviewController {
    public static func askForReview() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.foregroundActiveScene else { return }
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

extension UIApplication {
    var foregroundActiveScene: UIWindowScene? {
        connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }
}

extension Bundle {
    var releaseVersionNumber: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "no version number in plist"
    }
    
    var buildVersionNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "no build number in plist"
    }
}

public protocol ReviewUtilityLoggable: AnyObject {
    
    func log(_ message: String)
}

extension Calendar {
    private var currentDate: Date { Date() }
    
    func isDateInThisYear(_ date: Date) -> Bool {
        return isDate(date, equalTo: currentDate, toGranularity: .year)
    }
}

extension UIApplication {
    
    var isRunningInTestFlightEnvironment: Bool {
        if isSimulator {
            return false
        } else {
            if isAppStoreReceiptSandbox && !hasEmbeddedMobileProvision {
                return true
            } else {
                return false
            }
        }
    }
    
    var isRunningInAppStoreEnvironment: Bool {
        if isSimulator {
            return false
        } else {
            if isAppStoreReceiptSandbox || hasEmbeddedMobileProvision {
                return false
            } else {
                return true
            }
        }
    }

    private var hasEmbeddedMobileProvision: Bool {
        guard Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") == nil else {
            return true
        }
        return false
    }
    
    private var isAppStoreReceiptSandbox: Bool {
        if isSimulator {
            return false
        } else {
            guard let url = Bundle.main.appStoreReceiptURL else {
                return false
            }
            guard url.lastPathComponent == "sandboxReceipt" else {
                return false
            }
            return true
        }
    }
    
    private var isSimulator: Bool {
        #if arch(i386) || arch(x86_64)
        return true
        #else
        return false
        #endif
    }
}
