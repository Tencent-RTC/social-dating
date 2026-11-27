import UIKit
import Combine
import SnapKit
import AtomicXCore
import AtomicX

final class FriendApplicationListViewController: UIViewController {
    private let viewModel = FriendApplicationListViewModel()

    /// Host-supplied age / city pills shown after each nickname.
    private let tagProvider: ((String) -> UIView?)?

    init(tagProvider: ((String) -> UIView?)? = nil) {
        self.tagProvider = tagProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var applications: [FriendApplicationInfo] = []

    private var cancellables = Set<AnyCancellable>()

    private static let listTopInset: CGFloat = CGFloat(SpacingScheme.contentSpacing)

    private static let emptyFontSize: CGFloat = 17

    private static let estimatedRowHeight: CGFloat = FriendApplicationCell.rowHeight

    private static let navigationBarHeight: CGFloat = 44

    private static let toastDuration: TimeInterval = 3

    private static let searchEntryHeight: CGFloat = 36

    private static let searchEntryRadius: CGFloat = 10

    private static let searchEntryTop: CGFloat = 4

    private static let searchEntryBottom: CGFloat = 12

    private static let searchEntrySide: CGFloat = 16

    private static let sectionHeaderHeight: CGFloat = 32

    /// AtomicXCore drops an application from `friendApplicationList` once it is accepted, so the rows accepted during
    /// this visit are kept here (in memory only) and shown as "已添加" after the live ones.
    private var acceptedApplications: [FriendApplicationInfo] = []

    private var liveApplications: [FriendApplicationInfo] = []

    private var acceptedIDs: Set<String> { Set(acceptedApplications.map { $0.userID }) }

    private let searchContainer = UIView()

    private let searchInner = UIView()

    private let searchIcon = UIImageView()

    private let searchLabel = UILabel()

    private lazy var navigationBar = SubPageNavigationBar(title: LocalizedChatString("ContactsNewContactsTitle"))

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.separatorStyle = .none
        table.rowHeight = FriendApplicationCell.rowHeight
        table.estimatedRowHeight = Self.estimatedRowHeight
        if #available(iOS 15.0, *) {
            table.sectionHeaderTopPadding = 0
        }
        table.register(FriendApplicationCell.self, forCellReuseIdentifier: FriendApplicationCell.reuseIdentifier)
        return table
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = LocalizedChatString("ContactNoFriendApplication")
        label.font = .adaptiveSystemFont(ofSize: Self.emptyFontSize)
        label.textColor = TUIChatKitTheme.colors.textColorSecondary
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHierarchy()
        setupStyle()
        bindViewModel()
        viewModel.loadData()
    }

    private func setupHierarchy() {
        navigationBar.onClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        navigationBar.setTrailingAction(
            image: AtomicXChatResources.image(named: "contact_add_friend")?.withRenderingMode(.alwaysTemplate)
                ?? UIImage(systemName: "person.badge.plus"),
            accessibilityLabel: LocalizedChatString("ContactsAddFriend")
        ) { [weak self] in
            self?.openAddFriend()
        }
        searchContainer.addSubview(searchInner)
        searchInner.addSubview(searchIcon)
        searchInner.addSubview(searchLabel)
        searchInner.isUserInteractionEnabled = true
        searchInner.isAccessibilityElement = true
        searchInner.accessibilityTraits = .button
        searchInner.accessibilityLabel = LocalizedChatString("ContactsNewContactsSearchHint")
        searchInner.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSearchEntryTapped)))
        view.addSubview(navigationBar)
        view.addSubview(searchContainer)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        navigationBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.navigationBarHeight)
        }
        searchContainer.snp.makeConstraints { make in
            make.top.equalTo(navigationBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
        }
        searchInner.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Self.searchEntryTop)
            make.bottom.equalToSuperview().offset(-Self.searchEntryBottom)
            make.leading.equalToSuperview().offset(Self.searchEntrySide)
            make.trailing.equalToSuperview().offset(-Self.searchEntrySide)
            make.height.equalTo(Self.searchEntryHeight)
        }
        searchIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }
        searchLabel.snp.makeConstraints { make in
            make.leading.equalTo(searchIcon.snp.trailing).offset(6)
            make.trailing.lessThanOrEqualToSuperview().offset(-12)
            make.centerY.equalToSuperview()
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchContainer.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        emptyLabel.snp.makeConstraints { make in
            make.top.equalTo(searchContainer.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        tableView.dataSource = self
        tableView.delegate = self
    }

    private func setupStyle() {
        view.backgroundColor = TUIChatKitTheme.colors.bgColorTopBar
        tableView.backgroundColor = TUIChatKitTheme.colors.bgColorTopBar
        let colors = TUIChatKitTheme.colors
        searchContainer.backgroundColor = colors.bgColorTopBar
        searchInner.backgroundColor = colors.bgColorInput
        searchInner.layer.cornerRadius = Self.searchEntryRadius
        searchIcon.image = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        )
        searchIcon.tintColor = colors.textColorSecondary
        searchIcon.contentMode = .scaleAspectFit
        searchLabel.text = LocalizedChatString("ContactsNewContactsSearchHint")
        searchLabel.font = .adaptiveSystemFont(ofSize: 14)
        searchLabel.textColor = colors.textColorTertiary
    }

    private func bindViewModel() {
        viewModel.$applications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self = self else { return }
                self.liveApplications = list.filter { $0.type != .sent }
                self.renderApplications()
            }
            .store(in: &cancellables)
    }

    private func renderApplications() {
        let liveIDs = Set(liveApplications.map { $0.userID })
        let received = liveApplications + acceptedApplications.filter { !liveIDs.contains($0.userID) }
        applications = received
        emptyLabel.isHidden = !received.isEmpty
        tableView.isHidden = received.isEmpty
        tableView.reloadData()
    }

    private func accept(_ application: FriendApplicationInfo) {
        viewModel.accept(application) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    if !self.acceptedIDs.contains(application.userID) { self.acceptedApplications.append(application) }
                    self.renderApplications()
                    WindowToastManager.shared.show(LocalizedChatString("FriendRequestAccepted"), type: .success, duration: Self.toastDuration)
                case .failure:
                    WindowToastManager.shared.show(LocalizedChatString("FriendRequestAcceptFailed"), type: .error, duration: Self.toastDuration)
                }
            }
        }
    }

    private func openAddFriend() {
        let page = AddFriendViewController()
        let navigation = UINavigationController(rootViewController: page)
        navigation.setNavigationBarHidden(true, animated: false)
        navigation.modalPresentationStyle = .fullScreen
        page.onBack = { [weak navigation] in
            navigation?.dismiss(animated: true)
        }
        present(navigation, animated: true)
    }

    @objc private func handleSearchEntryTapped() {
        openAddFriend()
    }

    private func confirmRefuse(_ application: FriendApplicationInfo) {
        let name = ContactDisplayNameFormatter.name(for: application)
        WindowAlertManager.shared.showAlert(
            message: String(format: LocalizedChatString("ContactsRefuseConfirm"), name),
            cancelText: LocalizedChatString("Cancel"),
            confirmText: LocalizedChatString("Confirm"),
            onConfirm: { [weak self] in self?.refuse(application) }
        )
    }

    private func refuse(_ application: FriendApplicationInfo) {
        viewModel.refuse(application) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    WindowToastManager.shared.show(LocalizedChatString("FriendRequestDeclined"), type: .info, duration: Self.toastDuration)
                case .failure:
                    WindowToastManager.shared.show(LocalizedChatString("FriendRequestDeclineFailed"), type: .error, duration: Self.toastDuration)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension FriendApplicationListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return applications.isEmpty ? 0 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return applications.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: FriendApplicationCell.reuseIdentifier,
            for: indexPath
        ) as? FriendApplicationCell else {
            return UITableViewCell()
        }
        let application = applications[indexPath.row]
        cell.setTags(tagProvider?(application.userID))
        cell.configure(
            with: application,
            accepted: acceptedIDs.contains(application.userID),
            onAccept: { [weak self] in self?.accept(application) },
            onRefuse: { [weak self] in self?.confirmRefuse(application) }
        )
        return cell
    }
}

// MARK: - UITableViewDelegate

extension FriendApplicationListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Self.sectionHeaderHeight
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let colors = TUIChatKitTheme.colors
        let header = UIView()
        header.backgroundColor = colors.bgColorInput
        let label = UILabel()
        label.text = LocalizedChatString("ContactsReceivedGroup")
        label.font = .adaptiveSystemFont(ofSize: 14, weight: .bold)
        label.textColor = colors.textColorTertiary
        header.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.searchEntrySide)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.searchEntrySide)
            make.centerY.equalToSuperview()
        }
        return header
    }
}
