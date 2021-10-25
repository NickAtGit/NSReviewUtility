# NSReviewUtility

NSReviewUtility is a framework for counting app lauchnes and the happiness of a user in your app. It triggers the `SKStoreReviewController` review request when a certain condition happens.

## Usage example

Instatiate the NSReviewUtiltity in your AppDelegate. Both parameters are optional.:

    static let reviewUtility = NSReviewUtility(checkLaunchCountEvery: 5, checkHappinessIndexEvery: 3)

Then in `AppDelegate.didFinishLaunchingWithOptions`

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
                     
        // Triggers SKStoreReviewController review view when launchCount % 5 == 0
        AppDelegate.reviewUtility.incrementAppLauch()
        return true
    }

When something positive happens in your app:

    func somethingGoodHappened() {
        // Triggers SKStoreReviewController review view when happinessIndex % 3 == 0
        AppDelegate.reviewUtility.incrementHappiness()
    }
    
When something bad happened:
    
    func somethingBadHappened() {
        AppDelegate.reviewUtility.resetHappiness()
    }
    
To check the launchCount or happinessIndex you can call:

    AppDelegate.reviewUtility.launchCount
    AppDelegate.reviewUtility.happinessIndex

To see the framework live in action:

[NFC for iPhone on the AppStore](https://apps.apple.com/app/id1249686798)

The app increments the happiness when you successfully read a NFC tag or QR-code. When the happiness index reaches a multiple of 3 the review view is triggered.
