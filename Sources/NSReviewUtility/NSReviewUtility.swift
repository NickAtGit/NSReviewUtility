
import StoreKit

public class NSReviewUtility {
    
    private let appLaunchKey = "appLaunches"
    private let happinessIndexKey = "happinessIndex"
    
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
    
    private let appLaunchCountModuloCheck: Int?
    private let happinessIndexModuloCheck: Int?
    
    public init(checkLaunchCountEvery: Int? = nil,
                checkHappinessIndexEvery: Int? = nil) {
        self.appLaunchCountModuloCheck = checkLaunchCountEvery
        self.happinessIndexModuloCheck = checkHappinessIndexEvery
    }
    
    public func incrementAppLauch() {
        appLaunchCount += 1
        
        if let appLaunchCountModuloCheck = appLaunchCountModuloCheck {
            if appLaunchCount % appLaunchCountModuloCheck == 0,
               happinessIndex > 0 {
                showReviewIfNeeded()
            }
        }
    }
    
    public func incrementHappiness() {
        happinessIndex += 1
        
        if let happinessIndexModuloCheck = happinessIndexModuloCheck {
            if happinessIndex % happinessIndexModuloCheck == 0 {
                showReviewIfNeeded()
            }
        }
    }
    
    public func decrementHappiness() {
        happinessIndex -= 1
    }
    
    public func resetHappiness() {
        happinessIndex = 0
    }
        
    private func showReviewIfNeeded() {
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
