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

    // Total Input + Level card
    private let totalLevelCard = UIView()
    private let totalInputValue = UILabel()
    private let totalInputSubtitle = UILabel()
    private let levelHeader = UILabel()
    private let levelTrack = UIView()
    private let levelFill = UIView()
    private let levelLabel = UILabel()
    private var levelFillWidth: NSLayoutConstraint?

    private let viewStatsButton = UIButton(type: .system)

    // Predictions card
    private let predictionsCard = UIView()
    private let predictionsHeader = UILabel()
    private let predictionsVelocityLabel = UILabel()
    private let predictionsTrendLabel = UILabel()
    private let predictionsStack = UIStackView()

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
        setupTotalLevelCard()
        setupPredictionsCard()
        setupAllLevelsCard()

        stackView.addArrangedSubview(dailyGoalCard)
        stackView.addArrangedSubview(totalLevelCard)
        stackView.addArrangedSubview(predictionsCard)
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

    private func setupTotalLevelCard() {
        totalLevelCard.layer.cornerRadius = 12

        totalInputValue.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        totalInputValue.translatesAutoresizingMaskIntoConstraints = false
        totalLevelCard.addSubview(totalInputValue)

        totalInputSubtitle.font = UIFont.systemFont(ofSize: 13)
        totalInputSubtitle.numberOfLines = 0
        totalInputSubtitle.translatesAutoresizingMaskIntoConstraints = false
        totalLevelCard.addSubview(totalInputSubtitle)

        levelHeader.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        levelHeader.translatesAutoresizingMaskIntoConstraints = false
        totalLevelCard.addSubview(levelHeader)

        levelTrack.layer.cornerRadius = 6
        levelTrack.clipsToBounds = true
        levelTrack.translatesAutoresizingMaskIntoConstraints = false
        totalLevelCard.addSubview(levelTrack)

        levelFill.layer.cornerRadius = 6
        levelFill.translatesAutoresizingMaskIntoConstraints = false
        levelTrack.addSubview(levelFill)

        let fillWidth = levelFill.widthAnchor.constraint(equalToConstant: 0)
        levelFillWidth = fillWidth

        levelLabel.font = UIFont.systemFont(ofSize: 13)
        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLevelCard.addSubview(levelLabel)

        viewStatsButton.setTitle("View Stats", for: .normal)
        viewStatsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        viewStatsButton.addTarget(self, action: #selector(showStats), for: .touchUpInside)
        viewStatsButton.translatesAutoresizingMaskIntoConstraints = false
        totalLevelCard.addSubview(viewStatsButton)

        NSLayoutConstraint.activate([
            totalInputValue.topAnchor.constraint(equalTo: totalLevelCard.topAnchor, constant: 16),
            totalInputValue.leadingAnchor.constraint(equalTo: totalLevelCard.leadingAnchor, constant: 16),
            totalInputValue.trailingAnchor.constraint(equalTo: totalLevelCard.trailingAnchor, constant: -16),

            totalInputSubtitle.topAnchor.constraint(equalTo: totalInputValue.bottomAnchor, constant: 4),
            totalInputSubtitle.leadingAnchor.constraint(equalTo: totalLevelCard.leadingAnchor, constant: 16),
            totalInputSubtitle.trailingAnchor.constraint(equalTo: totalLevelCard.trailingAnchor, constant: -16),

            levelHeader.topAnchor.constraint(equalTo: totalInputSubtitle.bottomAnchor, constant: 16),
            levelHeader.leadingAnchor.constraint(equalTo: totalLevelCard.leadingAnchor, constant: 16),
            levelHeader.trailingAnchor.constraint(equalTo: totalLevelCard.trailingAnchor, constant: -16),

            levelTrack.topAnchor.constraint(equalTo: levelHeader.bottomAnchor, constant: 12),
            levelTrack.leadingAnchor.constraint(equalTo: totalLevelCard.leadingAnchor, constant: 16),
            levelTrack.trailingAnchor.constraint(equalTo: totalLevelCard.trailingAnchor, constant: -16),
            levelTrack.heightAnchor.constraint(equalToConstant: 12),

            levelFill.leadingAnchor.constraint(equalTo: levelTrack.leadingAnchor),
            levelFill.topAnchor.constraint(equalTo: levelTrack.topAnchor),
            levelFill.bottomAnchor.constraint(equalTo: levelTrack.bottomAnchor),
            fillWidth,

            levelLabel.topAnchor.constraint(equalTo: levelTrack.bottomAnchor, constant: 8),
            levelLabel.leadingAnchor.constraint(equalTo: totalLevelCard.leadingAnchor, constant: 16),
            levelLabel.trailingAnchor.constraint(equalTo: totalLevelCard.trailingAnchor, constant: -16),

            viewStatsButton.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 16),
            viewStatsButton.centerXAnchor.constraint(equalTo: totalLevelCard.centerXAnchor),
            viewStatsButton.bottomAnchor.constraint(equalTo: totalLevelCard.bottomAnchor, constant: -16)
        ])
    }

    private func setupPredictionsCard() {
        predictionsCard.layer.cornerRadius = 12

        predictionsHeader.text = "Predictions"
        predictionsHeader.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        predictionsHeader.translatesAutoresizingMaskIntoConstraints = false
        predictionsCard.addSubview(predictionsHeader)

        predictionsVelocityLabel.font = UIFont.systemFont(ofSize: 13)
        predictionsVelocityLabel.translatesAutoresizingMaskIntoConstraints = false
        predictionsCard.addSubview(predictionsVelocityLabel)

        predictionsTrendLabel.font = UIFont.systemFont(ofSize: 13)
        predictionsTrendLabel.translatesAutoresizingMaskIntoConstraints = false
        predictionsCard.addSubview(predictionsTrendLabel)

        predictionsStack.axis = .vertical
        predictionsStack.spacing = 0
        predictionsStack.translatesAutoresizingMaskIntoConstraints = false
        predictionsCard.addSubview(predictionsStack)

        NSLayoutConstraint.activate([
            predictionsHeader.topAnchor.constraint(equalTo: predictionsCard.topAnchor, constant: 16),
            predictionsHeader.leadingAnchor.constraint(equalTo: predictionsCard.leadingAnchor, constant: 16),
            predictionsHeader.trailingAnchor.constraint(equalTo: predictionsCard.trailingAnchor, constant: -16),

            predictionsVelocityLabel.topAnchor.constraint(equalTo: predictionsHeader.bottomAnchor, constant: 8),
            predictionsVelocityLabel.leadingAnchor.constraint(equalTo: predictionsCard.leadingAnchor, constant: 16),

            predictionsTrendLabel.centerYAnchor.constraint(equalTo: predictionsVelocityLabel.centerYAnchor),
            predictionsTrendLabel.leadingAnchor.constraint(equalTo: predictionsVelocityLabel.trailingAnchor, constant: 8),
            predictionsTrendLabel.trailingAnchor.constraint(lessThanOrEqualTo: predictionsCard.trailingAnchor, constant: -16),

            predictionsStack.topAnchor.constraint(equalTo: predictionsVelocityLabel.bottomAnchor, constant: 12),
            predictionsStack.leadingAnchor.constraint(equalTo: predictionsCard.leadingAnchor, constant: 16),
            predictionsStack.trailingAnchor.constraint(equalTo: predictionsCard.trailingAnchor, constant: -16),
            predictionsStack.bottomAnchor.constraint(equalTo: predictionsCard.bottomAnchor, constant: -16)
        ])
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
        totalLevelCard.backgroundColor = cardBg
        predictionsCard.backgroundColor = cardBg
        allLevelsCard.backgroundColor = cardBg

        let headerColor = ThemeColor.primaryText01()
        dailyGoalHeader.textColor = headerColor
        totalInputValue.textColor = headerColor
        levelHeader.textColor = headerColor
        predictionsHeader.textColor = headerColor
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
        updateTotalLevelCard()
        updatePredictionsCard()
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

    private func updateTotalLevelCard() {
        guard let totalSeconds = DreamingManager.shared.cachedTotalInputSeconds else {
            totalInputValue.text = "--"
            totalInputSubtitle.text = ""
            levelHeader.text = "Level --"
            levelLabel.text = "--"
            levelFillWidth?.constant = 0
            return
        }

        let totalHours = totalSeconds / 3600.0

        // Total input
        totalInputValue.text = "\(Int(totalHours)) hours"

        let platformHours = Int((DreamingManager.shared.cachedPlatformWatchTimeSeconds ?? 0) / 3600)
        let externalHours = Int((DreamingManager.shared.cachedExternalTimeSeconds ?? 0) / 3600)
        totalInputSubtitle.text = "\(platformHours)h from Dreaming Spanish \u{00B7} \(externalHours)h external"

        // Level progress
        let thresholds = Self.levelThresholds

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
            points.append(.init(date: date, cumulativeHours: cumulative, goalReached: entry.goalReached))
        }

        return points
    }

    private func updatePredictionsCard() {
        predictionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let (velocity, predictions) = DreamingManager.shared.calculateMilestonePredictions() else {
            predictionsCard.isHidden = true
            return
        }
        predictionsCard.isHidden = false

        let primaryText = ThemeColor.primaryText01()
        let subtitleText = ThemeColor.primaryText02()

        predictionsVelocityLabel.text = String(format: "%.1fh/day", velocity.velocity)
        predictionsVelocityLabel.textColor = primaryText

        let trendText: String
        let trendColor: UIColor
        switch velocity.trend {
        case .increasing:
            trendText = "\u{2197} Increasing"
            trendColor = ThemeColor.support02()
        case .decreasing:
            trendText = "\u{2198} Decreasing"
            trendColor = ThemeColor.support05()
        case .stable:
            trendText = "\u{2192} Stable"
            trendColor = subtitleText
        }
        predictionsTrendLabel.text = trendText
        predictionsTrendLabel.textColor = trendColor

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        for prediction in predictions {
            let row = UIView()

            let levelLabel = UILabel()
            levelLabel.text = "Level \(prediction.milestoneLevel) — \(Int(prediction.milestoneHours))h"
            levelLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            levelLabel.textColor = primaryText
            levelLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(levelLabel)

            let detailStack = UIStackView()
            detailStack.axis = .vertical
            detailStack.alignment = .trailing
            detailStack.spacing = 2
            detailStack.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(detailStack)

            let dateLabel = UILabel()
            dateLabel.text = dateFormatter.string(from: prediction.estimatedDate)
            dateLabel.font = UIFont.systemFont(ofSize: 13)
            dateLabel.textColor = primaryText
            dateLabel.textAlignment = .right
            detailStack.addArrangedSubview(dateLabel)

            let rangeLabel = UILabel()
            rangeLabel.text = "\(dateFormatter.string(from: prediction.optimisticDate)) – \(dateFormatter.string(from: prediction.pessimisticDate))"
            rangeLabel.font = UIFont.systemFont(ofSize: 11)
            rangeLabel.textColor = subtitleText
            rangeLabel.textAlignment = .right
            detailStack.addArrangedSubview(rangeLabel)

            NSLayoutConstraint.activate([
                levelLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                levelLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                detailStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                detailStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                detailStack.leadingAnchor.constraint(greaterThanOrEqualTo: levelLabel.trailingAnchor, constant: 8),
                row.heightAnchor.constraint(equalToConstant: 48)
            ])

            predictionsStack.addArrangedSubview(row)
        }
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

    // MARK: - Stats Modal

    @objc private func showStats() {
        guard #available(iOS 16.0, *) else { return }
        let statsView = DreamingStatsView(
            chartDataPoints: buildChartDataPoints(),
            levelThresholds: Self.levelThresholds,
            externalTimes: DreamingManager.shared.cachedExternalTimes ?? [],
            dayWatchedTimes: DreamingManager.shared.cachedDayWatchedTimes ?? []
        )
        let hostingController = UIHostingController(rootView: statsView)
        present(hostingController, animated: true)
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
