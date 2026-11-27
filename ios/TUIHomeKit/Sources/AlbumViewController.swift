import UIKit
import AtomicX
import TUIHostBase

public final class AlbumViewController: DemoSubPageController {
    private let userKey: String
    private var profile: HomeUserDetail?
    private let body = UIStackView()
    private let state = HostStateView()
    private var tokens: ColorTokens { Host.tokens }

    public init(userKey: String) {
        self.userKey = userKey
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = tokens.bgColorTopBar
        let header = HostHeaderView(title: DemoText.get("demo_album"), left: backButton())
        body.axis = .vertical
        let scroll = UIScrollView()
        scroll.backgroundColor = tokens.bgColorDefault
        scroll.showsVerticalScrollIndicator = false
        for item in [header, scroll, body, state] { item.translatesAutoresizingMaskIntoConstraints = false }
        scroll.addSubview(body)
        view.addSubview(scroll)
        view.addSubview(state)
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            state.topAnchor.constraint(equalTo: header.bottomAnchor), state.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            state.leadingAnchor.constraint(equalTo: view.leadingAnchor), state.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor)
        ])
        load()
    }

    private func load() {
        if let cached = HomeKit.cachedDetail(userKey) {
            profile = cached
            return render()
        }
        state.showLoading()
        HomeKit.dataSource.loadUserDetail(userKey: userKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let detail):
                    HomeKit.cacheDetail(self.userKey, detail)
                    self.profile = detail
                    self.state.hide()
                    self.render()
                case .failure:
                    self.state.showError { [weak self] in self?.load() }
                }
            }
        }
    }

    private func render() {
        guard let profile else { return }
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        body.addArrangedSubview(grid(profile))
    }

    private func wrap(_ content: UIView, _ insets: UIEdgeInsets) -> UIView {
        let wrapper = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -insets.right)
        ])
        return wrapper
    }

    /// `.pgrid`: three columns, 2pt gaps, 118pt tiles; the last tile of a long album is a video.
    private func grid(_ profile: HomeUserDetail) -> UIView {
        let photos = profile.albumPhotos
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 2
        for start in stride(from: 0, to: photos.count, by: 3) {
            let slice = Array(photos[start..<min(start + 3, photos.count)])
            var tiles: [UIView] = slice.enumerated().map { column, name in
                let video = start + column == photos.count - 1 && photos.count > 3
                let tile = ProfileUI.thumb(name, radius: 0, videoBadge: video ? 32 : 0) { [weak self] in
                    guard let self else { return }
                    HomeKit.actions.albumPhotoTapped(from: self, user: profile.card, photo: name)
                }
                tile.translatesAutoresizingMaskIntoConstraints = false
                tile.heightAnchor.constraint(equalToConstant: 118).isActive = true
                return tile
            }
            while tiles.count < 3 { tiles.append(UIView()) }
            let row = UIStackView(arrangedSubviews: tiles)
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 2
            rows.addArrangedSubview(row)
        }
        return rows
    }
}
