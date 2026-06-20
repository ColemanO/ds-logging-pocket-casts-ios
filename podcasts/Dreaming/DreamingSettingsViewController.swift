import UIKit

class DreamingSettingsViewController: PCViewController, UITextFieldDelegate {

    // MARK: - Dreaming Spanish section

    private let dreamingTokenField: ThemeableTextField = {
        let field = ThemeableTextField()
        field.placeholder = "Bearer Token"
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let dreamingSaveButton: ThemeableRoundedButton = {
        let button = ThemeableRoundedButton()
        button.setTitle("Save Token", for: .normal)
        button.buttonStyle = .primaryInteractive01
        button.textStyle = .primaryInteractive02
        button.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let dreamingStatusLabel: ThemeableLabel = {
        let label = ThemeableLabel()
        label.style = .primaryText02
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let dreamingRemoveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove Token", for: .normal)
        button.setTitleColor(ThemeColor.support05(), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - YouTube section

    private let youtubeSectionLabel: ThemeableLabel = {
        let label = ThemeableLabel()
        label.style = .primaryText01
        label.text = "YouTube API Key"
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let youtubeApiKeyField: ThemeableTextField = {
        let field = ThemeableTextField()
        field.placeholder = "API Key"
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let youtubeSaveButton: ThemeableRoundedButton = {
        let button = ThemeableRoundedButton()
        button.setTitle("Save API Key", for: .normal)
        button.buttonStyle = .primaryInteractive01
        button.textStyle = .primaryInteractive02
        button.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let youtubeStatusLabel: ThemeableLabel = {
        let label = ThemeableLabel()
        label.style = .primaryText02
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let youtubeRemoveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove API Key", for: .normal)
        button.setTitleColor(ThemeColor.support05(), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Keyboard

    private var saveButtonBottomConstraint: NSLayoutConstraint!
    private var originalButtonConstant: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Auth Settings"

        dreamingTokenField.delegate = self
        youtubeApiKeyField.delegate = self
        setupUI()
        updateStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        dreamingTokenField.resignFirstResponder()
        youtubeApiKeyField.resignFirstResponder()
    }

    private func setupUI() {
        let dreamingSectionLabel = ThemeableLabel()
        dreamingSectionLabel.style = .primaryText01
        dreamingSectionLabel.text = "Dreaming Spanish"
        dreamingSectionLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        dreamingSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        let divider = UIView()
        divider.backgroundColor = ThemeColor.primaryUi05()
        divider.translatesAutoresizingMaskIntoConstraints = false

        for subview in [
            dreamingSectionLabel, dreamingTokenField, dreamingSaveButton,
            dreamingStatusLabel, dreamingRemoveButton,
            divider,
            youtubeSectionLabel, youtubeApiKeyField, youtubeSaveButton,
            youtubeStatusLabel, youtubeRemoveButton
        ] {
            view.addSubview(subview)
        }

        dreamingSaveButton.addTarget(self, action: #selector(dreamingSaveTapped), for: .touchUpInside)
        dreamingRemoveButton.addTarget(self, action: #selector(dreamingRemoveTapped), for: .touchUpInside)
        youtubeSaveButton.addTarget(self, action: #selector(youtubeSaveTapped), for: .touchUpInside)
        youtubeRemoveButton.addTarget(self, action: #selector(youtubeRemoveTapped), for: .touchUpInside)

        saveButtonBottomConstraint = youtubeSaveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        originalButtonConstant = saveButtonBottomConstraint.constant

        NSLayoutConstraint.activate([
            // Dreaming Spanish section
            dreamingSectionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            dreamingSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dreamingSectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            dreamingTokenField.topAnchor.constraint(equalTo: dreamingSectionLabel.bottomAnchor, constant: 12),
            dreamingTokenField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dreamingTokenField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            dreamingTokenField.heightAnchor.constraint(equalToConstant: 44),

            dreamingStatusLabel.topAnchor.constraint(equalTo: dreamingTokenField.bottomAnchor, constant: 12),
            dreamingStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dreamingStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            dreamingRemoveButton.topAnchor.constraint(equalTo: dreamingStatusLabel.bottomAnchor, constant: 16),
            dreamingRemoveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            dreamingSaveButton.topAnchor.constraint(equalTo: dreamingRemoveButton.bottomAnchor, constant: 16),
            dreamingSaveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dreamingSaveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            dreamingSaveButton.heightAnchor.constraint(equalToConstant: 44),

            // Divider
            divider.topAnchor.constraint(equalTo: dreamingSaveButton.bottomAnchor, constant: 32),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // YouTube section
            youtubeSectionLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 24),
            youtubeSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            youtubeSectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            youtubeApiKeyField.topAnchor.constraint(equalTo: youtubeSectionLabel.bottomAnchor, constant: 12),
            youtubeApiKeyField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            youtubeApiKeyField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            youtubeApiKeyField.heightAnchor.constraint(equalToConstant: 44),

            youtubeStatusLabel.topAnchor.constraint(equalTo: youtubeApiKeyField.bottomAnchor, constant: 12),
            youtubeStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            youtubeStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            youtubeRemoveButton.topAnchor.constraint(equalTo: youtubeStatusLabel.bottomAnchor, constant: 16),
            youtubeRemoveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            saveButtonBottomConstraint,
            youtubeSaveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            youtubeSaveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            youtubeSaveButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func updateStatus() {
        let hasDreamingToken = DreamingManager.shared.hasToken
        dreamingStatusLabel.text = hasDreamingToken ? "Token saved" : "No token configured"
        dreamingRemoveButton.isHidden = !hasDreamingToken

        let hasYouTubeKey = DreamingManager.shared.hasYouTubeApiKey
        youtubeStatusLabel.text = hasYouTubeKey ? "API key saved" : "No API key configured"
        youtubeRemoveButton.isHidden = !hasYouTubeKey
    }

    // MARK: - Actions

    @objc private func dreamingSaveTapped() {
        guard let token = dreamingTokenField.text, !token.isEmpty else { return }
        DreamingManager.shared.saveToken(token)
        dreamingTokenField.text = ""
        dreamingTokenField.resignFirstResponder()
        updateStatus()
    }

    @objc private func dreamingRemoveTapped() {
        DreamingManager.shared.removeToken()
        updateStatus()
    }

    @objc private func youtubeSaveTapped() {
        guard let key = youtubeApiKeyField.text, !key.isEmpty else { return }
        DreamingManager.shared.saveYouTubeApiKey(key)
        youtubeApiKeyField.text = ""
        youtubeApiKeyField.resignFirstResponder()
        updateStatus()
    }

    @objc private func youtubeRemoveTapped() {
        DreamingManager.shared.removeYouTubeApiKey()
        updateStatus()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == dreamingTokenField {
            dreamingSaveTapped()
        } else if textField == youtubeApiKeyField {
            youtubeSaveTapped()
        }
        return true
    }

    // MARK: - Keyboard

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        let keyboardHeight = keyboardFrame.height - view.safeAreaInsets.bottom
        saveButtonBottomConstraint.constant = originalButtonConstant - keyboardHeight
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        saveButtonBottomConstraint.constant = originalButtonConstant
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    override func handleThemeChanged() {
        dreamingRemoveButton.setTitleColor(ThemeColor.support05(), for: .normal)
        youtubeRemoveButton.setTitleColor(ThemeColor.support05(), for: .normal)
    }
}
