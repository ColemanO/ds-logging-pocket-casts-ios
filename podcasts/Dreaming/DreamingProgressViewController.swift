import SwiftUI
import UIKit

class DreamingProgressViewController: PCViewController {

    // MARK: - Level Thresholds

    private static let levelThresholds: [(level: Int, hours: Double)] = [
        (1, 0), (2, 50), (3, 150), (4, 300), (5, 600), (6, 1000), (7, 1500)
    ]

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let refreshControl = UIRefreshControl()
    private let stackView = UIStackView()
    private let emptyStateLabel = UILabel()

    // Daily Goal card
    private let dailyGoalCard = UIView()
    private let dailyGoalHeader = UILabel()
    private let dailyGoalTrack = UIView()
    private let dailyGoalFill = UIView()
    private let dailyGoalLabel = UILabel()
    private var dailyGoalFillWidth: NSLayoutConstraint?

    // Total Input card
    private let totalInputCard = UIView()
    private let totalInputHeader = UILabel()
    private let totalInputValue = UILabel()
    private let totalInputSubtitle = UILabel()

    // Level Progress card
    private let levelCard = UIView()
    private let levelHeader = UILabel()
    private let levelTrack = UIView()
    private let levelFill = UIView()
    private let levelLabel = UILabel()
    private var levelFillWidth: NSLayoutConstraint?

    // Progress Chart card
    private let chartCard = UIView()
    private var chartHostingController: UIViewController?

    // All Levels card
    private let allLevelsCard = UIView()
    private let allLevelsHeader = UILabel()
    private let allLevelsStack = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dreaming"
        setupUI()
        applyThemeColors()

        NotificationCenter.default.addObserver(self, selector: #selector(handleLogStatusChanged), name: Constants.Notifications.dreamingLogStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTokenChanged), name: Constants.Notifications.dreamingTokenChanged, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshData()
    }

    override func handleThemeChanged() {
        applyThemeColors()
    }

    // MARK: - Setup

    private func setupUI() {
        // Empty state
        emptyStateLabel.text = "Set up your Dreaming Spanish token in Settings > Dreaming to track your progress"
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = UIFont.systemFont(ofSize: 16)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // Scroll view + pull to refresh
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scrollView.applyInsetForMiniPlayer()

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        setupDailyGoalCard()
        setupTotalInputCard()
        setupLevelCard()
        setupChartCard()
        setupAllLevelsCard()

        stackView.addArrangedSubview(dailyGoalCard)
        stackView.addArrangedSubview(totalInputCard)
        stackView.addArrangedSubview(levelCard)
        stackView.addArrangedSubview(chartCard)
        stackView.addArrangedSubview(allLevelsCard)
    }

    private func setupDailyGoalCard() {
        dailyGoalCard.layer.cornerRadius = 12

        dailyGoalHeader.text = "Daily Goal"
        dailyGoalHeader.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        dailyGoalHeader.translatesAutoresizingMaskIntoConstraints = false
        dailyGoalCard.addSubview(dailyGoalHeader)

        dailyGoalTrack.layer.cornerRadius = 6
        dailyGoalTrack.clipsToBounds = true
        dailyGoalTrack.translatesAutoresizingMaskIntoConstraints = false
        dailyGoalCard.addSubview(dailyGoalTrack)

        dailyGoalFill.layer.cornerRadius = 6
        dailyGoalFill.translatesAutoresizingMaskIntoConstraints = false
        dailyGoalTrack.addSubview(dailyGoalFill)

        let fillWidth = dailyGoalFill.widthAnchor.constraint(equalToConstant: 0)
        dailyGoalFillWidth = fillWidth

        dailyGoalLabel.font = UIFont.systemFont(ofSize: 13)
        dailyGoalLabel.translatesAutoresizingMaskIntoConstraints = false
        dailyGoalCard.addSubview(dailyGoalLabel)

        NSLayoutConstraint.activate([
            dailyGoalHeader.topAnchor.constraint(equalTo: dailyGoalCard.topAnchor, constant: 16),
            dailyGoalHeader.leadingAnchor.constraint(equalTo: dailyGoalCard.leadingAnchor, constant: 16),
            dailyGoalHeader.trailingAnchor.constraint(equalTo: dailyGoalCard.trailingAnchor, constant: -16),

            dailyGoalTrack.topAnchor.constraint(equalTo: dailyGoalHeader.bottomAnchor, constant: 12),
            dailyGoalTrack.leadingAnchor.constraint(equalTo: dailyGoalCard.leadingAnchor, constant: 16),
            dailyGoalTrack.trailingAnchor.constraint(equalTo: dailyGoalCard.trailingAnchor, constant: -16),
            dailyGoalTrack.heightAnchor.constraint(equalToConstant: 12),

            dailyGoalFill.leadingAnchor.constraint(equalTo: dailyGoalTrack.leadingAnchor),
            dailyGoalFill.topAnchor.constraint(equalTo: dailyGoalTrack.topAnchor),
            dailyGoalFill.bottomAnchor.constraint(equalTo: dailyGoalTrack.bottomAnchor),
            fillWidth,

            dailyGoalLabel.topAnchor.constraint(equalTo: dailyGoalTrack.bottomAnchor, constant: 8),
            dailyGoalLabel.leadingAnchor.constraint(equalTo: dailyGoalCard.leadingAnchor, constant: 16),
            dailyGoalLabel.trailingAnchor.constraint(equalTo: dailyGoalCard.trailingAnchor, constant: -16),
            dailyGoalLabel.bottomAnchor.constraint(equalTo: dailyGoalCard.bottomAnchor, constant: -16)
        ])
    }

    private func setupTotalInputCard() {
        totalInputCard.layer.cornerRadius = 12

        totalInputHeader.text = "Total Input"
        totalInputHeader.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        totalInputHeader.translatesAutoresizingMaskIntoConstraints = false
        totalInputCard.addSubview(totalInputHeader)

        totalInputValue.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        totalInputValue.translatesAutoresizingMaskIntoConstraints = false
        totalInputCard.addSubview(totalInputValue)

        totalInputSubtitle.font = UIFont.systemFont(ofSize: 13)
        totalInputSubtitle.numberOfLines = 0
        totalInputSubtitle.translatesAutoresizingMaskIntoConstraints = false
        totalInputCard.addSubview(totalInputSubtitle)

        NSLayoutConstraint.activate([
            totalInputHeader.topAnchor.constraint(equalTo: totalInputCard.topAnchor, constant: 16),
            totalInputHeader.leadingAnchor.constraint(equalTo: totalInputCard.leadingAnchor, constant: 16),
            totalInputHeader.trailingAnchor.constraint(equalTo: totalInputCard.trailingAnchor, constant: -16),

            totalInputValue.topAnchor.constraint(equalTo: totalInputHeader.bottomAnchor, constant: 8),
            totalInputValue.leadingAnchor.constraint(equalTo: totalInputCard.leadingAnchor, constant: 16),
            totalInputValue.trailingAnchor.constraint(equalTo: totalInputCard.trailingAnchor, constant: -16),

            totalInputSubtitle.topAnchor.constraint(equalTo: totalInputValue.bottomAnchor, constant: 4),
            totalInputSubtitle.leadingAnchor.constraint(equalTo: totalInputCard.leadingAnchor, constant: 16),
            totalInputSubtitle.trailingAnchor.constraint(equalTo: totalInputCard.trailingAnchor, constant: -16),
            totalInputSubtitle.bottomAnchor.constraint(equalTo: totalInputCard.bottomAnchor, constant: -16)
        ])
    }

    private func setupLevelCard() {
        levelCard.layer.cornerRadius = 12

        levelHeader.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        levelHeader.translatesAutoresizingMaskIntoConstraints = false
        levelCard.addSubview(levelHeader)

        levelTrack.layer.cornerRadius = 6
        levelTrack.clipsToBounds = true
        levelTrack.translatesAutoresizingMaskIntoConstraints = false
        levelCard.addSubview(levelTrack)

        levelFill.layer.cornerRadius = 6
        levelFill.translatesAutoresizingMaskIntoConstraints = false
        levelTrack.addSubview(levelFill)

        let fillWidth = levelFill.widthAnchor.constraint(equalToConstant: 0)
        levelFillWidth = fillWidth

        levelLabel.font = UIFont.systemFont(ofSize: 13)
        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        levelCard.addSubview(levelLabel)

        NSLayoutConstraint.activate([
            levelHeader.topAnchor.constraint(equalTo: levelCard.topAnchor, constant: 16),
            levelHeader.leadingAnchor.constraint(equalTo: levelCard.leadingAnchor, constant: 16),
            levelHeader.trailingAnchor.constraint(equalTo: levelCard.trailingAnchor, constant: -16),

            levelTrack.topAnchor.constraint(equalTo: levelHeader.bottomAnchor, constant: 12),
            levelTrack.leadingAnchor.constraint(equalTo: levelCard.leadingAnchor, constant: 16),
            levelTrack.trailingAnchor.constraint(equalTo: levelCard.trailingAnchor, constant: -16),
            levelTrack.heightAnchor.constraint(equalToConstant: 12),

            levelFill.leadingAnchor.constraint(equalTo: levelTrack.leadingAnchor),
            levelFill.topAnchor.constraint(equalTo: levelTrack.topAnchor),
            levelFill.bottomAnchor.constraint(equalTo: levelTrack.bottomAnchor),
            fillWidth,

            levelLabel.topAnchor.constraint(equalTo: levelTrack.bottomAnchor, constant: 8),
            levelLabel.leadingAnchor.constraint(equalTo: levelCard.leadingAnchor, constant: 16),
            levelLabel.trailingAnchor.constraint(equalTo: levelCard.trailingAnchor, constant: -16),
            levelLabel.bottomAnchor.constraint(equalTo: levelCard.bottomAnchor, constant: -16)
        ])
    }

    private func setupChartCard() {
        chartCard.layer.cornerRadius = 12
    }

    private func setupAllLevelsCard() {
        allLevelsCard.layer.cornerRadius = 12

        allLevelsHeader.text = "All Levels"
        allLevelsHeader.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        allLevelsHeader.translatesAutoresizingMaskIntoConstraints = false
        allLevelsCard.addSubview(allLevelsHeader)

        allLevelsStack.axis = .vertical
        allLevelsStack.spacing = 0
        allLevelsStack.translatesAutoresizingMaskIntoConstraints = false
        allLevelsCard.addSubview(allLevelsStack)

        NSLayoutConstraint.activate([
            allLevelsHeader.topAnchor.constraint(equalTo: allLevelsCard.topAnchor, constant: 16),
            allLevelsHeader.leadingAnchor.constraint(equalTo: allLevelsCard.leadingAnchor, constant: 16),
            allLevelsHeader.trailingAnchor.constraint(equalTo: allLevelsCard.trailingAnchor, constant: -16),

            allLevelsStack.topAnchor.constraint(equalTo: allLevelsHeader.bottomAnchor, constant: 12),
            allLevelsStack.leadingAnchor.constraint(equalTo: allLevelsCard.leadingAnchor, constant: 16),
            allLevelsStack.trailingAnchor.constraint(equalTo: allLevelsCard.trailingAnchor, constant: -16),
            allLevelsStack.bottomAnchor.constraint(equalTo: allLevelsCard.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Theme

    private func applyThemeColors() {
        view.backgroundColor = AppTheme.viewBackgroundColor()
        emptyStateLabel.textColor = ThemeColor.primaryText02()

        let cardBg = ThemeColor.primaryUi02()
        dailyGoalCard.backgroundColor = cardBg
        totalInputCard.backgroundColor = cardBg
        levelCard.backgroundColor = cardBg
        chartCard.backgroundColor = cardBg
        allLevelsCard.backgroundColor = cardBg

        let headerColor = ThemeColor.primaryText01()
        dailyGoalHeader.textColor = headerColor
        totalInputHeader.textColor = headerColor
        totalInputValue.textColor = headerColor
        levelHeader.textColor = headerColor
        allLevelsHeader.textColor = headerColor

        let subtitleColor = ThemeColor.primaryText02()
        dailyGoalLabel.textColor = subtitleColor
        totalInputSubtitle.textColor = subtitleColor
        levelLabel.textColor = subtitleColor

        let trackColor = ThemeColor.primaryUi05()
        dailyGoalTrack.backgroundColor = trackColor
        levelTrack.backgroundColor = trackColor

        // Re-apply fill colors based on current data
        updateFillColors()
    }

    private func updateFillColors() {
        let goalReached: Bool
        if let watched = DreamingManager.shared.cachedTodayWatchedSeconds,
           let goal = DreamingManager.shared.cachedDailyGoalSeconds, goal > 0 {
            goalReached = watched >= Double(goal)
        } else {
            goalReached = false
        }
        dailyGoalFill.backgroundColor = goalReached ? ThemeColor.support02() : ThemeColor.primaryInteractive01()
        levelFill.backgroundColor = ThemeColor.primaryInteractive01()
    }

    // MARK: - Data

    private func refreshData() {
        let hasToken = DreamingManager.shared.hasToken
        emptyStateLabel.isHidden = hasToken
        scrollView.isHidden = !hasToken

        guard hasToken else { return }

        DreamingManager.shared.refreshProgressData { [weak self] in
            self?.refreshControl.endRefreshing()
            self?.updateCards()
        }
    }

    private func updateCards() {
        updateDailyGoalCard()
        updateTotalInputCard()
        updateLevelCard()
        updateChartCard()
        updateAllLevelsCard()
        updateFillColors()
    }

    private func updateDailyGoalCard() {
        guard let watched = DreamingManager.shared.cachedTodayWatchedSeconds,
              let goal = DreamingManager.shared.cachedDailyGoalSeconds, goal > 0 else {
            dailyGoalLabel.text = "--"
            dailyGoalFillWidth?.constant = 0
            return
        }

        let fraction = min(watched / Double(goal), 1.0)
        dailyGoalLabel.text = "\(formatTime(seconds: watched)) / \(formatTime(seconds: Double(goal)))"

        dailyGoalTrack.layoutIfNeeded()
        dailyGoalFillWidth?.constant = dailyGoalTrack.bounds.width * fraction
        UIView.animate(withDuration: 0.3) {
            self.dailyGoalTrack.layoutIfNeeded()
        }
    }

    private func updateTotalInputCard() {
        guard let totalSeconds = DreamingManager.shared.cachedTotalInputSeconds else {
            totalInputValue.text = "--"
            totalInputSubtitle.text = ""
            return
        }

        let totalHours = Int(totalSeconds / 3600)
        totalInputValue.text = "\(totalHours) hours"

        let platformHours = Int((DreamingManager.shared.cachedPlatformWatchTimeSeconds ?? 0) / 3600)
        let externalHours = Int((DreamingManager.shared.cachedExternalTimeSeconds ?? 0) / 3600)
        totalInputSubtitle.text = "\(platformHours)h from Dreaming Spanish \u{00B7} \(externalHours)h external"
    }

    private func updateLevelCard() {
        guard let totalSeconds = DreamingManager.shared.cachedTotalInputSeconds else {
            levelHeader.text = "Level --"
            levelLabel.text = "--"
            levelFillWidth?.constant = 0
            return
        }

        let totalHours = totalSeconds / 3600.0
        let thresholds = Self.levelThresholds

        // Find current level
        var currentLevel = thresholds[0]
        var nextLevel: (level: Int, hours: Double)?
        for i in 0 ..< thresholds.count {
            if totalHours >= thresholds[i].hours {
                currentLevel = thresholds[i]
                nextLevel = (i + 1 < thresholds.count) ? thresholds[i + 1] : nil
            }
        }

        levelHeader.text = "Level \(currentLevel.level)"

        if let next = nextLevel {
            let hoursToNext = Int(next.hours - totalHours)
            levelLabel.text = "\(hoursToNext) hours to Level \(next.level)"

            let rangeSize = next.hours - currentLevel.hours
            let progress = rangeSize > 0 ? (totalHours - currentLevel.hours) / rangeSize : 1.0
            let fraction = min(max(progress, 0), 1.0)

            levelTrack.layoutIfNeeded()
            levelFillWidth?.constant = levelTrack.bounds.width * fraction
            UIView.animate(withDuration: 0.3) {
                self.levelTrack.layoutIfNeeded()
            }
        } else {
            levelLabel.text = "Max level reached!"
            levelTrack.layoutIfNeeded()
            levelFillWidth?.constant = levelTrack.bounds.width
            UIView.animate(withDuration: 0.3) {
                self.levelTrack.layoutIfNeeded()
            }
        }
    }

    private func updateChartCard() {
        guard #available(iOS 16.0, *) else { return }

        let dataPoints = buildChartDataPoints()
        let chartView = DreamingProgressChartView(
            dataPoints: dataPoints,
            levelThresholds: Self.levelThresholds
        )

        // Remove previous hosting controller
        if let existing = chartHostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }

        let hostingController = UIHostingController(rootView: chartView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        chartCard.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: chartCard.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: chartCard.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        chartHostingController = hostingController
    }

    private func buildChartDataPoints() -> [DreamingProgressChartView.DataPoint] {
        guard #available(iOS 16.0, *) else { return [] }
        guard let dayTimes = DreamingManager.shared.cachedDayWatchedTimes, !dayTimes.isEmpty else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // Add initial external time (input prior to Dreaming Spanish) to the baseline
        var initialSeconds = 0.0
        if let externalTimes = DreamingManager.shared.cachedExternalTimes {
            initialSeconds = externalTimes
                .filter { $0.type == "initial" }
                .reduce(0.0) { $0 + $1.timeSeconds }
        }

        let sorted = dayTimes.sorted { $0.date < $1.date }
        var cumulative = initialSeconds / 3600.0
        var points: [DreamingProgressChartView.DataPoint] = []

        for entry in sorted {
            guard let date = formatter.date(from: entry.date) else { continue }
            cumulative += entry.timeSeconds / 3600.0
            points.append(.init(date: date, cumulativeHours: cumulative))
        }

        return points
    }

    private func updateAllLevelsCard() {
        allLevelsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let totalSeconds = DreamingManager.shared.cachedTotalInputSeconds ?? 0
        let totalHours = totalSeconds / 3600.0
        let dailyGoalSeconds = DreamingManager.shared.cachedDailyGoalSeconds ?? 0
        let dailyGoalHours = Double(dailyGoalSeconds) / 3600.0

        let primaryText = ThemeColor.primaryText01()
        let subtitleText = ThemeColor.primaryText02()
        let reachedColor = ThemeColor.support02()

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        for threshold in Self.levelThresholds {
            let row = UIView()

            let levelLabel = UILabel()
            levelLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            levelLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(levelLabel)

            let detailStack = UIStackView()
            detailStack.axis = .vertical
            detailStack.alignment = .trailing
            detailStack.spacing = 2
            detailStack.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(detailStack)

            let detailLabel = UILabel()
            detailLabel.font = UIFont.systemFont(ofSize: 13)
            detailLabel.textAlignment = .right

            let dateLabel = UILabel()
            dateLabel.font = UIFont.systemFont(ofSize: 12)
            dateLabel.textAlignment = .right

            let reached = totalHours >= threshold.hours

            levelLabel.text = "Level \(threshold.level) — \(Int(threshold.hours))h"
            levelLabel.textColor = reached ? reachedColor : primaryText

            if reached {
                detailLabel.text = "Reached"
                detailLabel.textColor = reachedColor
                detailStack.addArrangedSubview(detailLabel)
            } else {
                let hoursRemaining = threshold.hours - totalHours
                if dailyGoalHours > 0 {
                    let days = Int(ceil(hoursRemaining / dailyGoalHours))
                    detailLabel.text = "\(days) days"
                    let estimatedDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                    dateLabel.text = dateFormatter.string(from: estimatedDate)
                } else {
                    detailLabel.text = "\(Int(ceil(hoursRemaining)))h remaining"
                }
                detailLabel.textColor = subtitleText
                dateLabel.textColor = subtitleText
                detailStack.addArrangedSubview(detailLabel)
                if dailyGoalHours > 0 {
                    detailStack.addArrangedSubview(dateLabel)
                }
            }

            NSLayoutConstraint.activate([
                levelLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                levelLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                detailStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                detailStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                detailStack.leadingAnchor.constraint(greaterThanOrEqualTo: levelLabel.trailingAnchor, constant: 8),
                row.heightAnchor.constraint(equalToConstant: 44)
            ])

            allLevelsStack.addArrangedSubview(row)
        }
    }

    // MARK: - Helpers

    private func formatTime(seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Notifications

    @objc private func handlePullToRefresh() {
        refreshData()
    }

    @objc private func handleLogStatusChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshData()
        }
    }

    @objc private func handleTokenChanged() {
        refreshData()
    }
}
