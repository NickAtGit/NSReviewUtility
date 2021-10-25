# NSReviewUtility

NSReviewUtility is a framework for counting app lauchnes and the happiness of a user in your app. It triggers the `SKStoreReviewController` review request when a certain condition happens.

## Usage example

Instatiate the NSReviewUtiltity in your AppDelegate. Both parameters are optional. The Ap:

    static let reviewUtility = NSReviewUtility(checkLaunchCountEvery: 5, checkHappinessIndexEvery: 3)

Then in `didFinishLaunchingWithOptions`

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
                     
        AppDelegate.reviewUtility.incrementAppLauch()
        return true
    }

When something positive happens in your app:

    func somethingGoodHappened() {
        AppDelegate.reviewUtility.incrementHappiness()
    }
    
When something bad happened:
    
    func somethingBadHappened() {
        AppDelegate.reviewUtility.resetHappiness()
    }
