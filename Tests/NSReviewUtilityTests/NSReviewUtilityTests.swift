import Foundation
import Testing
@testable import NSReviewUtility

/// A movable clock so cooldown / yearly-cap logic is deterministic.
private final class Clock {
    var date: Date
    init(_ date: Date) { self.date = date }
    func advance(days: Int) { date = date.addingTimeInterval(TimeInterval(days) * 86_400) }
    var now: () -> Date { { [unowned self] in self.date } }
}

private func makeDefaults() -> UserDefaults {
    let suite = "NSReviewUtilityTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: iso)!
}

/// A fresh utility started at `clock`, with `firstLaunch` far enough in the past to clear the age
/// gate by default, and the given policy applied.
private func makeUtility(
    clock: Clock,
    version: String = "1.0.0-1",
    policy: ReviewPromptPolicy = .default,
    defaults: UserDefaults? = nil
) -> (NSReviewUtility, UserDefaults) {
    let defaults = defaults ?? makeDefaults()
    // Seed a first-launch date 30 days before the clock so `daysAfterFirstLaunch: 3` is satisfied.
    defaults.set(clock.date.addingTimeInterval(-30 * 86_400), forKey: "firstLaunchDate")
    let utility = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: version)
    utility.start()
    utility.configure(with: policy)
    return (utility, defaults)
}

@Suite("Eligibility")
struct EligibilityTests {
    @Test("Fresh user below the happiness threshold is denied notHappyEnough")
    func belowThreshold() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        utility.incrementHappiness()  // index 1, threshold 3
        #expect(utility.eligibility() == .denied(.notHappyEnough))
    }

    @Test("Crossing the threshold makes the user eligible")
    func crossesThreshold() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        for _ in 0..<3 { utility.incrementHappiness() }
        #expect(utility.eligibility() == .eligible)
    }

    @Test("Age gate blocks a brand new install regardless of happiness")
    func ageGate() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let defaults = makeDefaults()
        defaults.set(clock.date, forKey: "firstLaunchDate")  // launched right now
        let utility = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "1.0.0-1")
        utility.start()
        utility.configure(with: ReviewPromptPolicy(happinessThreshold: 3, daysAfterFirstLaunch: 3))
        for _ in 0..<10 { utility.incrementHappiness() }
        #expect(utility.eligibility() == .denied(.tooSoonAfterFirstLaunch))
    }

    @Test("Happiness requirement matrix")
    func happinessMatrix() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock, policy: ReviewPromptPolicy(happinessThreshold: 3, daysAfterFirstLaunch: 3))
        // index 0
        #expect(utility.eligibility(happiness: .ignored) == .eligible)
        #expect(utility.eligibility(happiness: .anyPositive) == .denied(.notHappyEnough))
        #expect(utility.eligibility(happiness: .threshold) == .denied(.notHappyEnough))
        utility.incrementHappiness()  // index 1
        #expect(utility.eligibility(happiness: .anyPositive) == .eligible)
        #expect(utility.eligibility(happiness: .threshold) == .denied(.notHappyEnough))
        utility.incrementHappiness(); utility.incrementHappiness()  // index 3
        #expect(utility.eligibility(happiness: .threshold) == .eligible)
    }
}

@Suite("Claiming")
struct ClaimingTests {
    @Test("Claim succeeds once then blocks on the same version")
    func claimOnce() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        for _ in 0..<3 { utility.incrementHappiness() }
        #expect(utility.claimPrompt(trigger: "organic") == true)
        #expect(utility.claimPrompt(trigger: "organic") == false)
        #expect(utility.eligibility(happiness: .ignored) == .denied(.alreadyAskedThisVersion))
    }

    @Test("Two claims in one run of the loop yield exactly one true")
    func atomicClaim() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        for _ in 0..<3 { utility.incrementHappiness() }
        let a = utility.claimPrompt(trigger: "organic")
        let b = utility.claimPrompt(trigger: "detailBack", happiness: .anyPositive)
        #expect([a, b].filter { $0 }.count == 1)
    }

    @Test("Claim consumes happiness")
    func consumeOnPrompt() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        for _ in 0..<5 { utility.incrementHappiness() }
        _ = utility.claimPrompt(trigger: "organic")
        #expect(utility.happinessIndex == 0)
    }

    @Test("A new build version re-arms the prompt")
    func newVersionReArms() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let defaults = makeDefaults()
        let (utility, _) = makeUtility(clock: clock, version: "1.0.0-1", defaults: defaults)
        for _ in 0..<3 { utility.incrementHappiness() }
        #expect(utility.claimPrompt(trigger: "organic") == true)

        // Same stored data, new build.
        let next = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "1.0.1-2")
        next.start()
        next.configure(with: .default)
        for _ in 0..<3 { next.incrementHappiness() }
        #expect(next.eligibility() == .eligible)
    }

    @Test("Force bypasses eligibility but still records")
    func forceClaim() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        // index 0, would be denied
        #expect(utility.eligibility() == .denied(.notHappyEnough))
        #expect(utility.claimPrompt(trigger: "devMenu", force: true) == true)
        #expect(utility.eligibility(happiness: .ignored) == .denied(.alreadyAskedThisVersion))
    }
}

@Suite("Yearly cap")
struct YearlyCapTests {
    @Test("Three prompts across versions, fourth blocked, resets next year")
    func capBindsAndResets() {
        // The cap is hardcoded to 3 (mirrors Apple's own yearly prompt limit), not configurable.
        let clock = Clock(date("2026-01-10T12:00:00Z"))
        let defaults = makeDefaults()
        defaults.set(clock.date.addingTimeInterval(-30 * 86_400), forKey: "firstLaunchDate")

        func claim(version: String) -> Bool {
            let u = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: version)
            u.start()
            u.configure(with: .default)
            for _ in 0..<3 { u.incrementHappiness() }
            return u.claimPrompt(trigger: "organic")
        }

        #expect(claim(version: "1.0.0-1") == true)
        #expect(claim(version: "1.0.1-2") == true)
        #expect(claim(version: "1.0.2-3") == true)
        #expect(claim(version: "1.0.3-4") == false)  // cap reached

        // Verify the denial reason.
        let capped = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "1.0.4-5")
        capped.start(); capped.configure(with: .default)
        for _ in 0..<3 { capped.incrementHappiness() }
        #expect(capped.eligibility() == .denied(.yearlyCapReached))

        // Roll into next year.
        clock.advance(days: 365)
        #expect(claim(version: "2.0.0-10") == true)
    }
}

@Suite("Migration")
struct MigrationTests {
    @Test("Previously-asked heavy user is not re-asked on update")
    func legacyInstallStaggered() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let defaults = makeDefaults()
        // Simulate a long-lived install: old build, high happiness, asked a year ago.
        defaults.set([clock.date.addingTimeInterval(-300 * 86_400)], forKey: "datesAskedForReview")
        defaults.set(clock.date.addingTimeInterval(-400 * 86_400), forKey: "firstLaunchDate")
        defaults.set(47, forKey: "happinessIndex")
        defaults.set("5.31.0-1", forKey: "versionLastAskedForReview")

        let utility = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "6.0.0-1")
        utility.start()
        utility.configure(with: .default)

        // Version guard released, but happiness was consumed by migration, so the card does not fire.
        #expect(utility.happinessIndex == 0)
        #expect(utility.eligibility() == .denied(.notHappyEnough))
    }

    @Test("Never-asked user keeps their happiness across migration")
    func neverAskedUserKeepsHappiness() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let defaults = makeDefaults()
        defaults.set(clock.date.addingTimeInterval(-30 * 86_400), forKey: "firstLaunchDate")
        defaults.set(5, forKey: "happinessIndex")
        // versionLastAskedForReview absent → sentinel → never asked.

        let utility = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "6.0.0-1")
        utility.start()
        utility.configure(with: .default)

        #expect(utility.happinessIndex == 5)
        #expect(utility.eligibility() == .eligible)
    }

    @Test("Migration runs once")
    func migrationIdempotent() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let defaults = makeDefaults()
        defaults.set([clock.date], forKey: "datesAskedForReview")
        defaults.set(clock.date.addingTimeInterval(-30 * 86_400), forKey: "firstLaunchDate")
        defaults.set(20, forKey: "happinessIndex")
        defaults.set("5.31.0-1", forKey: "versionLastAskedForReview")

        let first = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "6.0.0-1")
        first.start()
        #expect(first.happinessIndex == 0)

        // Earn happiness again, then a second start must not wipe it.
        for _ in 0..<4 { first.incrementHappiness() }
        let second = NSReviewUtility(defaults: defaults, now: clock.now, currentVersion: "6.0.0-1")
        second.start()
        #expect(second.happinessIndex == 4)
    }
}

@Suite("Native prompt quota")
struct NativeQuotaTests {
    @Test("Native prompt gets a single shot per year, then falls through to the App Store")
    func singleNativeShotPerYear() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        #expect(utility.hasNativePromptQuota == true)
        utility.requestNativeReview()
        // One request spends the year's native shot; further taps must not reopen it.
        #expect(utility.hasNativePromptQuota == false)
        utility.requestNativeReview()
        utility.requestNativeReview()
        #expect(utility.hasNativePromptQuota == false)
        // Card dedupe ledger is untouched by native requests.
        #expect(utility.datesPromptShown.isEmpty)
    }

    @Test("Native shot resets the following calendar year")
    func nativeShotResetsNextYear() {
        let clock = Clock(date("2026-06-01T12:00:00Z"))
        let (utility, _) = makeUtility(clock: clock)
        utility.requestNativeReview()
        #expect(utility.hasNativePromptQuota == false)
        clock.date = date("2027-01-02T12:00:00Z")
        #expect(utility.hasNativePromptQuota == true)
    }
}
