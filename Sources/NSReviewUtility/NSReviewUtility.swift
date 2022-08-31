
import StoreKit

@available(iOS 14.0, *)
public class NSReviewUtility: ObservableObject {

    @Published public private(set) var canAskForReview = false
    
    public var happinessIndexCheckCount: Int { didSet { evaluateCanAskForReview() } }
    public var daysAfterFirstLaunchCheckCount: Int { didSet { evaluateCanAskForReview() } }

    private var isDateDaysAfterFirstLaunchCheckCount: Bool {
        if let firstLaunchDate {
            let thresholdDate = firstLaunchDate.addingTimeInterval(TimeInterval(daysAfterFirstLaunchCheckCount * 60 * 60 * 24))
            return Date() > thresholdDate
        } else {
            return false
        }
    }
    
    private weak var loggingAdapter: ReviewUtilityLoggable?
        
    public init(happinessIndexCheckCount: Int = 5,
                daysAfterFirstLaunchCheckCount: Int = 3,
                loggingAdapter: ReviewUtilityLoggable? = nil) {
        
        self.happinessIndexCheckCount = happinessIndexCheckCount
        self.daysAfterFirstLaunchCheckCount = daysAfterFirstLaunchCheckCount
        self.loggingAdapter = loggingAdapter
        
        if let firstLaunchDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            loggingAdapter?.log("⭐️ ReviewUtility started. First launched at \(formatter.string(from: firstLaunchDate)), happinessIndexCheckCount: \(happinessIndexCheckCount), daysAfterFirstLaunchCheckCount: \(daysAfterFirstLaunchCheckCount)")
        } else {
            firstLaunchDate = Date()
            loggingAdapter?.log("⭐️ ReviewUtility started for the first time. Setting first launched date to now.")
        }
        
        evaluateCanAskForReview()
    }
    
    private func evaluateCanAskForReview() {
        let askedForReviewThisYearCount = datesAskedForReview.filter { Calendar.current.isDateInThisYear($0) }.count
        let hasLessThanThreeReviewAttemptsThisYear = askedForReviewThisYearCount <= 3
        var logString = "⭐️ ReviewUtility asked \(askedForReviewThisYearCount) times this year for a review."

        let isUserHappy = happinessIndex != 0 && (happinessIndex % happinessIndexCheckCount == 0)
        
        if let versionLastAskedForReview,
           let currentVersion = Bundle.main.releaseVersionNumber {
            let versionNotMatching = versionLastAskedForReview != currentVersion
            logString += " Asked for rating at version: \(versionLastAskedForReview), current version is: \(currentVersion)."
            canAskForReview = versionNotMatching && isDateDaysAfterFirstLaunchCheckCount && hasLessThanThreeReviewAttemptsThisYear && isUserHappy
        } else {
            logString += " currentDate > thresholdDate: \(isDateDaysAfterFirstLaunchCheckCount)."
            canAskForReview = isDateDaysAfterFirstLaunchCheckCount && hasLessThanThreeReviewAttemptsThisYear && isUserHappy
        }
        logString += " Can ask for review: \(canAskForReview)"
        loggingAdapter?.log(logString)
    }
    
    public func incrementHappiness() {
        happinessIndex += 1
        loggingAdapter?.log("⭐️ Incremeting happiness, index is now: \(happinessIndex)")
        evaluateCanAskForReview()
    }
    
    public func decrementHappiness() {
        happinessIndex -= 1
        loggingAdapter?.log("⭐️ Decremeting happiness, index is now: \(happinessIndex)")
    }
    
    public func resetHappiness() {
        happinessIndex = 0
        loggingAdapter?.log("⭐️ Resetting happiness, index is now: \(happinessIndex)")
    }
    
    public func askForReview(force: Bool = false) {
        
        let askForReviewClosure = { [weak self] in
            self?.loggingAdapter?.log("⭐️ Asking for review now")
            self?.datesAskedForReview.append(Date())
            self?.versionLastAskedForReview = Bundle.main.releaseVersionNumber
            SKStoreReviewController.askForReview()
        }
        
        if force {
            askForReviewClosure()
        } else if canAskForReview {
            askForReviewClosure()
        } else {
            loggingAdapter?.log("⭐️ Can not ask for review")
        }
    }
    
    public func clearAllData() {
        datesAskedForReview = []
        firstLaunchDate = nil
        happinessIndex = 0
        versionLastAskedForReview = nil
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
    
    public private(set) var versionLastAskedForReview: String? {
        get {
            UserDefaults.standard.string(forKey: "versionLastAskedForReview")
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
            guard let scene = UIApplication.shared.windows.first?.windowScene else { return }
            requestReview(in: scene)
        }
    }
}

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
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
