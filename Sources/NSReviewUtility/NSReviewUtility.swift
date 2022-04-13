
import StoreKit

public class NSReviewUtility {
    
    public static let shared = NSReviewUtility()
    private init() {}
    
    public private(set) var appLaunchCount: Int {
        get {
            UserDefaults.standard.value(forKey: appLaunchKey) as? Int ?? 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: appLaunchKey)
        }
    }
    
    public private(set) var happinessIndex: Int {
        get {
            UserDefaults.standard.value(forKey: happinessIndexKey) as? Int ?? 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: happinessIndexKey)
        }
    }
    
    public var appLaunchCheckCount = 3
    public var happinessIndexCheckCount = 3
    
    private let appLaunchKey = "appLaunches"
    private let happinessIndexKey = "happinessIndex"
    
    public func incrementAppLauch() {
        appLaunchCount += 1
        
        if appLaunchCount % appLaunchCheckCount == 0,
           happinessIndex > 0 {
            askForReview()
        }
    }
    
    public func incrementHappiness() {
        happinessIndex += 1
        
        if happinessIndex % happinessIndexCheckCount == 0 {
            askForReview()
        }
    }
    
    public func decrementHappiness() {
        happinessIndex -= 1
    }
    
    public func resetHappiness() {
        happinessIndex = 0
    }
    
    public func askForReview() {
        SKStoreReviewController.requestReviewInCurrentScene()
    }
}

extension SKStoreReviewController {
    public static func requestReviewInCurrentScene() {
        DispatchQueue.main.async {
            if #available(iOS 14.0, *) {
                if let scene = UIApplication.shared.windows.first?.windowScene {
                    requestReview(in: scene)
                }
            } else {
                SKStoreReviewController.requestReview()
            }
        }
    }
}
