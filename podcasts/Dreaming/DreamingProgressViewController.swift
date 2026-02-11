import UIKit

class DreamingProgressViewController: PCViewController {

    // MARK: - Level Thresholds

    private static let levelThresholds: [(level: Int, hours: Double)] = [
        (1, 0), (2, 50), (3, 150), (4, 300), (5, 600), (6, 1000), (7, 1500)
    ]

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
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

        // Scroll view + stack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

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

        stackView.addArrangedSubview(dailyGoalCard)
        stackView.addArrangedSubview(totalInputCard)
        stackView.addArrangedSubview(levelCard)
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

    // MARK: - Theme

    private func applyThemeColors() {
        view.backgroundColor = AppTheme.viewBackgroundColor()
        emptyStateLabel.textColor = ThemeColor.primaryText02()

        let cardBg = ThemeColor.primaryUi02()
        dailyGoalCard.backgroundColor = cardBg
        totalInputCard.backgroundColor = cardBg
        levelCard.backgroundColor = cardBg

        let headerColor = ThemeColor.primaryText01()
        dailyGoalHeader.textColor = headerColor
        totalInputHeader.textColor = headerColor
        totalInputValue.textColor = headerColor
        levelHeader.textColor = headerColor

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
            self?.updateCards()
        }
    }

    private func updateCards() {
        updateDailyGoalCard()
        updateTotalInputCard()
        updateLevelCard()
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

    @objc private func handleLogStatusChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshData()
        }
    }

    @objc private func handleTokenChanged() {
        refreshData()
    }
}
