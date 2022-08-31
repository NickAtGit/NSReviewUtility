# NSReviewUtility

NSReviewUtility is a package for counting the happiness of a user in your app. It triggers the `SKStoreReviewController` review request when a certain condition happens. You can specify the `happinessIndexCheckCount` and the `daysAfterFirstLaunchCheckCount` to control when the `SKStoreReviewController` should appear at first. The package prevents asking for review when the dialogue already appeared on your current app version or you asked more than three times a year. The ideas for that are from this blog post [Increase App Ratings by using SKStoreReviewController](https://www.avanderlee.com/swift/skstorereviewcontroller-app-ratings/)

## Usage example

Create a adapter class in your project.:

    import NSReviewUtility
    
    class ReviewUtilityAdapter {
        
        let reviewUtility: NSReviewUtility
        private static let reviewUtilityLoggingAdapter = ReviewUtilityLoggerAdapter()
        
        init() {
            self.reviewUtility = NSReviewUtility(happinessIndexCheckCount: 5,
                                                 daysAfterFirstLaunchCheckCount: 3,
                                                 loggingAdapter: ReviewUtilityAdapter.reviewUtilityLoggingAdapter)
        }
    }
    
    class ReviewUtilityLoggerAdapter: ReviewUtilityLoggable {
        func log(_ message: String) {
            //Do your logging here
        }
    }
    
Put this as a free variable in your project:
    
    let reviewUtility = ReviewUtilityAdapter().reviewUtility

When something positive happens in your app:

    func somethingPositiveHappened() {
        reviewUtility.incrementHappiness()
    }
    
When something negative happens in your app:

    func somethingNegativeHappened() {
        reviewUtility.decrementHappiness()
    }

When something really bad happened:
    
    func somethingReallyBadHappened() {
        reviewUtility.resetHappiness()
    }
    
You can also ask for review when possible:

    func manuallyAskForReview() {
        reviewUtility.askForReview()
    }

To see this package live in action:

[NFC・QR Code・Document Scanner on the AppStore](https://apps.apple.com/app/id1249686798)
