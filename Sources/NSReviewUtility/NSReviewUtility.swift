
import StoreKit

@available(iOS 14.0, *)
public class NSReviewUtility {
    
    private let happinessIndexCheckCount: Int
    private let daysAfterFirstLaunchCheckCount: Int
    private var loggingAdapter: ReviewUtilityLoggable?
    
    init(happinessIndexCheckCount: Int = 5,
         daysAfterFirstLaunchCheckCount: Int = 7,
         loggingAdapter: ReviewUtilityLoggable? = nil) {
        
        self.happinessIndexCheckCount = happinessIndexCheckCount
        self.daysAfterFirstLaunchCheckCount = daysAfterFirstLaunchCheckCount
        self.loggingAdapter = loggingAdapter
        
        if let firstLaunchDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            loggingAdapter?.log("⭐️ ReviewUtility started. First launched at \(formatter.string(from: firstLaunchDate))")
        } else {
            firstLaunchDate = Date()
            loggingAdapter?.log("⭐️ ReviewUtility started for the first time. Setting frist launched date to now.")
        }
        
        let askedForReviewThisYearCount = datesAskedForReview.filter { Calendar.current.isDateInThisYear($0) }.count
        let hasLessThanThreeReviewAttemptsThisYear = askedForReviewThisYearCount <= 3
        loggingAdapter?.log("⭐️ ReviewUtility asked \(askedForReviewThisYearCount) times this year for a review.")

        if let versionLastAskedForReview,
           let currentVersion = Bundle.main.releaseVersionNumber {
            let versionNotMatching = versionLastAskedForReview != currentVersion
            loggingAdapter?.log("⭐️ Asked for rating at version: \(versionLastAskedForReview), current version is: \(currentVersion)")
            canAskForReview = versionNotMatching && isDateDaysAfterFirstLaunchCheckCount && hasLessThanThreeReviewAttemptsThisYear
        } else {
            canAskForReview = isDateDaysAfterFirstLaunchCheckCount && hasLessThanThreeReviewAttemptsThisYear
        }
    }
    
    private var canAskForReview = false {
        didSet {
            loggingAdapter?.log("⭐️ Can ask for review: \(canAskForReview)")
        }
    }
    private var didAskForReview = false
    private var isDateDaysAfterFirstLaunchCheckCount: Bool {
        if let firstLaunchDate {
            let thresholdDate = firstLaunchDate.addingTimeInterval(TimeInterval(daysAfterFirstLaunchCheckCount * 60 * 60 * 24))
            
            let isCurrentDateGreaterThanThresholdDate = Date() > thresholdDate
            loggingAdapter?.log("⭐️ Is current date greater than threshold date: \(isCurrentDateGreaterThanThresholdDate)")
            return isCurrentDateGreaterThanThresholdDate
        } else {
            return false
        }
    }
        
    public func incrementHappiness() {
        happinessIndex += 1
        loggingAdapter?.log("⭐️ Incremeting happiness, index is now: \(happinessIndex)")

        if canAskForReview && happinessIndex >= happinessIndexCheckCount {
            askForReview()
        }
    }
    
    public func decrementHappiness() {
        happinessIndex -= 1
        loggingAdapter?.log("⭐️ Decremeting happiness, index is now: \(happinessIndex)")
    }
    
    public func resetHappiness() {
        happinessIndex = 0
        loggingAdapter?.log("⭐️ Resetting happiness, index is now: \(happinessIndex)")
    }
    
    public func askForReview() {
        if canAskForReview {
            loggingAdapter?.log("⭐️ Asking for review now")
            datesAskedForReview.append(Date())
            SKStoreReviewController.askForReview()
        }
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
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

public protocol ReviewUtilityLoggable {
    
    func log(_ message: String)
}

extension Calendar {
    private var currentDate: Date { Date() }
    
    func isDateInThisYear(_ date: Date) -> Bool {
        return isDate(date, equalTo: currentDate, toGranularity: .year)
    }
}
