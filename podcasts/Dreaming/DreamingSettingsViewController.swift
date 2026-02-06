import UIKit

class DreamingSettingsViewController: PCViewController, UITextFieldDelegate {
    private let tokenField: ThemeableTextField = {
        let field = ThemeableTextField()
        field.placeholder = "Bearer Token"
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let saveButton: ThemeableRoundedButton = {
        let button = ThemeableRoundedButton()
        button.setTitle("Save Token", for: .normal)
        button.buttonStyle = .primaryInteractive01
        button.textStyle = .primaryInteractive02
        button.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let statusLabel: ThemeableLabel = {
        let label = ThemeableLabel()
        label.style = .primaryText02
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove Token", for: .normal)
        button.setTitleColor(ThemeColor.support05(), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var saveButtonBottomConstraint: NSLayoutConstraint!
    private var originalButtonConstant: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dreaming"

        tokenField.delegate = self
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
        tokenField.resignFirstResponder()
    }

    private func setupUI() {
        view.addSubview(tokenField)
        view.addSubview(saveButton)
        view.addSubview(statusLabel)
        view.addSubview(removeButton)

        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        saveButtonBottomConstraint = saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        originalButtonConstant = saveButtonBottomConstraint.constant

        NSLayoutConstraint.activate([
            tokenField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            tokenField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tokenField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tokenField.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: tokenField.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            removeButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            removeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            saveButtonBottomConstraint
        ])
    }

    private func updateStatus() {
        let hasToken = DreamingManager.shared.hasToken
        statusLabel.text = hasToken ? "Token saved" : "No token configured"
        removeButton.isHidden = !hasToken
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        guard let token = tokenField.text, !token.isEmpty else { return }
        DreamingManager.shared.saveToken(token)
        tokenField.text = ""
        tokenField.resignFirstResponder()
        updateStatus()
    }

    @objc private func removeTapped() {
        DreamingManager.shared.removeToken()
        updateStatus()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveTapped()
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
        removeButton.setTitleColor(ThemeColor.support05(), for: .normal)
    }
}
