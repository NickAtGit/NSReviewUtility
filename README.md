# NSReviewUtility

NSReviewUtility is a package for counting the happiness of a user in your app. It triggers the `SKStoreReviewController` review request when a certain condition happens. You can specify the `happinessIndexCheckCount` and the `daysAfterFirstLaunchCheckCount` to control when the `SKStoreReviewController` should appear at first. The package prevents asking for review when the dialogue already appeared on your current app version or you asked more than three times a year. The ideas for that are from this blog post [Increase App Ratings by using SKStoreReviewController](https://www.avanderlee.com/swift/skstorereviewcontroller-app-ratings/)

## Usage example

Instatiate the NSReviewUtiltity in your AppDelegate. Both parameters are optional.:

    static let reviewUtility = NSReviewUtility(happinessIndexCheckCount: 5, daysAfterFirstLaunchCheckCount: 3)

When something positive happens in your app:

    func somethingPositiveHappened() {
        AppDelegate.reviewUtility.incrementHappiness()
    }
    
When something negative happens in your app:

    func somethingNegativeHappened() {
        AppDelegate.reviewUtility.decrementHappiness()
    }

When something really bad happened:
    
    func somethingReallyBadHappened() {
        AppDelegate.reviewUtility.resetHappiness()
    }
    
You can also ask for review when possible:

    func manuallyAskForReview() {
        AppDelegate.reviewUtility.askForReview()
    }

To see this package live in action:

[NFC・QR Code・Document Scanner on the AppStore](https://apps.apple.com/app/id1249686798)
