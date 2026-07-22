import StoreKit

#if os(iOS)
typealias Application = UIApplication
#else
typealias Application = NSApplication
#endif

// MARK: - Policy & eligibility

/// The remote-tunable rules that decide whether a review prompt may be shown.
/// Owned by the host app's config layer and pushed in via `configure(with:)`.
public struct ReviewPromptPolicy: Equatable, Sendable {
    public var isEnabled: Bool
    public var happinessThreshold: Int
    public var daysAfterFirstLaunch: Int
    public var maxPromptsPerYear: Int

    public init(isEnabled: Bool, happinessThreshold: Int, daysAfterFirstLaunch: Int, maxPromptsPerYear: Int) {
        self.isEnabled = isEnabled
        self.happinessThreshold = happinessThreshold
        self.daysAfterFirstLaunch = daysAfterFirstLaunch
        self.maxPromptsPerYear = maxPromptsPerYear
    }

    public static let `default` = ReviewPromptPolicy(
        isEnabled: true,
        happinessThreshold: 3,
        daysAfterFirstLaunch: 3,
        maxPromptsPerYear: 3
    )
}

/// How strongly a given trigger cares about accumulated happiness. Moment triggers (a good UX beat
/// like closing a detail screen) want a weaker bar than the organic "user seems happy" trigger.
public enum HappinessRequirement: Sendable {
    /// `happinessIndex >= policy.happinessThreshold`. The organic trigger.
    case threshold
    /// `happinessIndex > 0`. Preserves crash/failed-scan suppression without gating out light users.
    case anyPositive
    /// No happiness gate at all. For moments that fire before happiness can accrue (second app start).
    case ignored
}

public enum ReviewPromptDenial: String, Sendable {
    case disabledByPolicy
    case tooSoonAfterFirstLaunch
    case notHappyEnough
    case alreadyAskedThisVersion
    case yearlyCapReached
}

public enum ReviewPromptEligibility: Equatable, Sendable {
    case eligible
    case denied(ReviewPromptDenial)

    public var isEligible: Bool { self == .eligible }
}

// MARK: - NSReviewUtility

/// Single source of truth for "may we ask this user for a review, and have we already asked?".
///
/// The whole "shown once" guarantee rests on `claimPrompt`: it evaluates eligibility and records the
/// prompt as shown in one synchronous step, so two triggers racing at the same moment cannot both
/// present. Recording happens at presentation, not at outcome, which is what makes the yearly cap
/// actually count every card the user saw (including the ones they just dismissed).
///
/// Call `claimPrompt`, `configure` and the happiness mutators from the main thread; every real caller
/// already is (scan services, view actions, presentation code). Only the `@Published` mirror is
/// main-dispatched defensively.
public final class NSReviewUtility: ObservableObject {
    /// Mirror of `eligibility(happiness: .threshold)` for the organic `.onChange` trigger to observe.
    /// Not authoritative: `claimPrompt` recomputes eligibility synchronously so it never acts on a
    /// stale value.
    @Published public private(set) var canAskForReview = false

    private var policy: ReviewPromptPolicy = .default
    private let defaults: UserDefaults
    private let now: () -> Date
    private let currentVersion: String
    private weak var loggingAdapter: ReviewUtilityLoggable?

    static let notAskedSentinel = "not asked yet"
    private static let maxStoredDates = 12
    private static let storageVersion = 1

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        currentVersion: String = Bundle.main.releaseVersionNumber + "-" + Bundle.main.buildVersionNumber
    ) {
        self.defaults = defaults
        self.now = now
        self.currentVersion = currentVersion
    }

    public func start() {
        migrateLegacyStorageIfNeeded()
        if let firstLaunchDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            loggingAdapter?.log("⭐️ ReviewUtility started. First launched \(formatter.string(from: firstLaunchDate)).")
        } else {
            firstLaunchDate = now()
            loggingAdapter?.log("⭐️ ReviewUtility started for the first time. Setting first launch date to now.")
        }
        refresh()
    }

    public func setLoggingAdapter(_ loggingAdapter: ReviewUtilityLoggable) {
        self.loggingAdapter = loggingAdapter
    }

    /// Push the current remote config. Re-evaluates eligibility immediately, which the previous
    /// implementation deliberately avoided; safe now because re-evaluation only updates a `Bool`
    /// and can no longer fire a prompt on its own.
    public func configure(with policy: ReviewPromptPolicy) {
        self.policy = policy
        loggingAdapter?.log("⭐️ ReviewUtility configured: enabled=\(policy.isEnabled), happinessThreshold=\(policy.happinessThreshold), daysAfterFirstLaunch=\(policy.daysAfterFirstLaunch), maxPerYear=\(policy.maxPromptsPerYear)")
        refresh()
    }

    // MARK: Happiness

    public func incrementHappiness() {
        happinessIndex += 1
        loggingAdapter?.log("⭐️ Incrementing happiness, index is now: \(happinessIndex)")
        refresh()
    }

    public func decrementHappiness() {
        if happinessIndex > 0 {
            happinessIndex -= 1
            loggingAdapter?.log("⭐️ Decrementing happiness, index is now: \(happinessIndex)")
        } else {
            loggingAdapter?.log("⭐️ Can not decrement happiness because it is already \(happinessIndex)")
        }
        refresh()
    }

    public func resetHappiness() {
        happinessIndex = 0
        loggingAdapter?.log("⭐️ Resetting happiness, index is now: \(happinessIndex)")
        refresh()
    }

    // MARK: Eligibility & claiming

    public func eligibility(happiness: HappinessRequirement = .threshold) -> ReviewPromptEligibility {
        guard policy.isEnabled else { return .denied(.disabledByPolicy) }
        guard versionLastAskedForReview != currentVersion else { return .denied(.alreadyAskedThisVersion) }
        guard promptsThisYear < policy.maxPromptsPerYear else { return .denied(.yearlyCapReached) }
        guard isPastFirstLaunchDelay else { return .denied(.tooSoonAfterFirstLaunch) }
        guard meetsHappiness(happiness) else { return .denied(.notHappyEnough) }
        return .eligible
    }

    /// Atomically checks eligibility and, if eligible, records the prompt as shown. Returns `true` to
    /// exactly one caller in a run of the loop; that caller MUST present. `force` bypasses the
    /// eligibility checks (dev tooling) but still records, matching a real prompt for dedupe.
    @discardableResult
    public func claimPrompt(trigger: String, happiness: HappinessRequirement = .threshold, force: Bool = false) -> Bool {
        guard force else {
            let result = eligibility(happiness: happiness)
            guard result.isEligible else {
                loggingAdapter?.log("⭐️ Prompt denied for \(trigger): \(result)")
                return false
            }
            recordPromptShown()
            loggingAdapter?.log("⭐️ Prompt claimed for \(trigger)")
            return true
        }
        recordPromptShown()
        loggingAdapter?.log("⭐️ Prompt force-claimed for \(trigger)")
        return true
    }

    private func recordPromptShown() {
        datesPromptShown = Array((datesPromptShown + [now()]).suffix(Self.maxStoredDates))
        versionLastAskedForReview = currentVersion
        resetHappiness()
    }

    // MARK: Native prompt (Apple's yearly quota)

    /// Apple's `SKStoreReviewController` prompt is silently dropped once the user has been prompted,
    /// has disabled in-app reviews in Settings, or Apple's own cap is hit, and none of those are
    /// detectable. So the native prompt gets a single shot per calendar year: the first "rate" tap
    /// spends it, and every later tap falls through to the App Store instead of silently doing nothing.
    /// Deliberately independent of `maxPromptsPerYear`, which caps how often the *card* is shown, not
    /// how many native prompts a user may trigger. This also means repeated taps cannot keep burning
    /// quota: once the single yearly request is recorded, `handleRateTapped` stops asking for it.
    public var hasNativePromptQuota: Bool {
        nativeRequestsThisYear == 0
    }

    public func requestNativeReview() {
        datesNativeReviewRequested = Array((datesNativeReviewRequested + [now()]).suffix(Self.maxStoredDates))
        loggingAdapter?.log("⭐️ Requesting native review prompt")
        SKStoreReviewController.askForReview()
    }

    public func clearAllData() {
        datesPromptShown = []
        datesNativeReviewRequested = []
        firstLaunchDate = now()
        happinessIndex = 0
        versionLastAskedForReview = Self.notAskedSentinel
        loggingAdapter?.log("⭐️ Clearing all review data")
        refresh()
    }

    // MARK: - Private evaluation

    private func refresh() {
        let eligible = eligibility(happiness: .threshold).isEligible
        if Thread.isMainThread {
            canAskForReview = eligible
        } else {
            DispatchQueue.main.async { self.canAskForReview = eligible }
        }
    }

    private var promptsThisYear: Int {
        datesPromptShown.filter { Calendar.current.isDate($0, equalTo: now(), toGranularity: .year) }.count
    }

    private var nativeRequestsThisYear: Int {
        datesNativeReviewRequested.filter { Calendar.current.isDate($0, equalTo: now(), toGranularity: .year) }.count
    }

    private var isPastFirstLaunchDelay: Bool {
        guard let firstLaunchDate else { return false }
        let threshold = firstLaunchDate.addingTimeInterval(TimeInterval(policy.daysAfterFirstLaunch * 60 * 60 * 24))
        return now() > threshold
    }

    private func meetsHappiness(_ requirement: HappinessRequirement) -> Bool {
        switch requirement {
        case .ignored: return true
        case .anyPositive: return happinessIndex > 0
        case .threshold: return happinessIndex >= policy.happinessThreshold
        }
    }

    /// Existing installs carry a large `happinessIndex` and a `versionLastAskedForReview` pinned to an
    /// old build. Once a new build ships the version guard releases and a threshold check would pass
    /// instantly for the whole installed base at once. Applying consume-on-prompt retroactively (which
    /// the old code never did) staggers that: previously-asked users must re-earn happiness first.
    private func migrateLegacyStorageIfNeeded() {
        guard defaults.integer(forKey: Keys.storageVersion) < Self.storageVersion else { return }

        let legacy = defaults.value(forKey: LegacyKeys.datesAskedForReview) as? [Date] ?? []
        datesPromptShown = legacy
        datesNativeReviewRequested = legacy

        if versionLastAskedForReview != Self.notAskedSentinel {
            happinessIndex = 0
        }

        defaults.set(Self.storageVersion, forKey: Keys.storageVersion)
        loggingAdapter?.log("⭐️ Migrated legacy review storage to v\(Self.storageVersion)")
    }
}

// MARK: - Storage

extension NSReviewUtility {
    private enum Keys {
        static let storageVersion = "nsReviewUtility.storageVersion"
        static let datesPromptShown = "nsReviewUtility.datesPromptShown"
        static let datesNativeReviewRequested = "nsReviewUtility.datesNativeReviewRequested"
        // Retained under their legacy names so existing values carry across the migration untouched.
        static let firstLaunchDate = "firstLaunchDate"
        static let happinessIndex = "happinessIndex"
        static let versionLastAskedForReview = "versionLastAskedForReview"
    }

    private enum LegacyKeys {
        static let datesAskedForReview = "datesAskedForReview"
    }

    public private(set) var datesPromptShown: [Date] {
        get { defaults.value(forKey: Keys.datesPromptShown) as? [Date] ?? [] }
        set { defaults.set(newValue, forKey: Keys.datesPromptShown) }
    }

    public private(set) var datesNativeReviewRequested: [Date] {
        get { defaults.value(forKey: Keys.datesNativeReviewRequested) as? [Date] ?? [] }
        set { defaults.set(newValue, forKey: Keys.datesNativeReviewRequested) }
    }

    public private(set) var firstLaunchDate: Date? {
        get { defaults.value(forKey: Keys.firstLaunchDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.firstLaunchDate) }
    }

    public private(set) var happinessIndex: Int {
        get { defaults.integer(forKey: Keys.happinessIndex) }
        set { defaults.set(newValue, forKey: Keys.happinessIndex) }
    }

    private var versionLastAskedForReview: String {
        get { defaults.string(forKey: Keys.versionLastAskedForReview) ?? Self.notAskedSentinel }
        set { defaults.set(newValue, forKey: Keys.versionLastAskedForReview) }
    }
}

// MARK: - Native prompt plumbing

extension SKStoreReviewController {
    static func askForReview() {
        DispatchQueue.main.async {
            #if os(iOS)
            guard let scene = UIApplication.shared.foregroundActiveScene else { return }
            SKStoreReviewController.requestReview(in: scene)
            #else
            SKStoreReviewController.requestReview()
            #endif
        }
    }
}

#if os(iOS)
extension UIApplication {
    var foregroundActiveScene: UIWindowScene? {
        connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }
}
#endif

extension Bundle {
    public var releaseVersionNumber: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "no version number in plist"
    }

    public var buildVersionNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "no build number in plist"
    }
}

public protocol ReviewUtilityLoggable: AnyObject {
    func log(_ message: String)
}
