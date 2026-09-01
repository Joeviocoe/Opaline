// swiftlint:disable file_length
import UIKit

extension WatchViewController {
    private var actionBarItems: [ActionBarItem] {
        [
            ActionBarItem(
                button: likeButton,
                icon: "icon_thumb_up",
                label: nil,
                countLabel: likeCountLabel
            ),
            ActionBarItem(
                button: dislikeButton,
                icon: "icon_thumb_down",
                label: nil,
                countLabel: dislikeCountLabel
            ),
            ActionBarItem(
                button: shareButton,
                icon: "icon_share",
                label: "player.action.share".localized
            ),
            ActionBarItem(
                button: saveButton,
                icon: "icon_bookmark",
                label: "player.action.save".localized
            ),
            ActionBarItem(
                button: downloadButton,
                icon: "icon_download",
                label: "player.action.download".localized,
                countLabel: downloadStatusLabel
            )
        ]
    }

    @available(iOS 11.0, *)
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        adjustForFloatingNavBar()
    }

    func setupNavigationBar() {
        // Bar styling (appearance, tint, margins) is owned by
        // RotatingNavigationController so every bar lays out identically.
        navigationController?.setNavigationBarHidden(false, animated: false)
        updateLeftBarButton()
    }

    func addNotificationObservers() {
        let nc = NotificationCenter.default
        let tn = ThemeManager.didChangeNotification
        let bg = UIApplication.didEnterBackgroundNotification
        let fg = UIApplication.willEnterForegroundNotification
        nc.addObserver(self, selector: #selector(applyTheme), name: tn, object: nil)
        nc.addObserver(self, selector: #selector(appDidEnterBackground), name: bg, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground), name: fg, object: nil)
        nc.addObserver(
            self,
            selector: #selector(queueDidChange),
            name: PlaybackQueue.didChangeNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(audioTracksDidChange(_:)),
            name: .sourceAudioTracksDidChange,
            object: nil
        )
        addDownloadObservers()
        // Only to release the orientation lock a fullscreen toggle took — the
        // rotation itself is UIKit's job. Generation runs app-wide from
        // `AppDelegate`, so there is nothing to start here.
        if UIDevice.current.userInterfaceIdiom != .pad {
            nc.addObserver(
                self,
                selector: #selector(handleDeviceOrientationChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }
    }

    /// Both feed the same button: one fires when a job starts, finishes or is
    /// deleted, the other once a second while it runs.
    private func addDownloadObservers() {
        let nc = NotificationCenter.default
        for name in [
            DownloadStore.didChangeNotification,
            VideoDownloader.didProgressNotification
        ] {
            nc.addObserver(
                self,
                selector: #selector(updateDownloadButton),
                name: name,
                object: nil
            )
        }
    }

    func setupLayout() {
        setupScrollAndPlayer()
        setupPlayerOverlays()
        setupMetaViews()
        setupChannelViews()
        setupActionBar()
        setupCommentsSection()
        setupRelatedCollection()
        activateMetaConstraints()
        activateChannelConstraints()
        activateBottomConstraints()
        let sel = #selector(openChannel)
        channelAvatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: sel))
        channelNameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: sel))
    }

    func setupScrollAndPlayer() {
        for item in [scrollView, playerContainer, sidebarContainer, contentView] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        // `canCancelContentTouches` is what takes the touch back from a
        // related card once the finger starts scrolling. The pan must be
        // allowed to cancel touches for that to reach the cell — without it
        // the tap survives the whole drag and opens a video on lift-off.
        scrollView.canCancelContentTouches = true
        scrollView.delegate = self
        [scrollView, playerContainer, sidebarContainer, queueBar]
            .forEach { view.addSubview($0) }
        scrollView.addSubview(contentView)
        let pc = playerContainer, sv = scrollView
        let sc = sidebarContainer, safe = view.safeAreaLayoutGuide
        scrollTrailingConstraint = sv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        scrollToSidebarConstraint = sv.trailingAnchor.constraint(equalTo: sc.leadingAnchor)
        playerTopConstraint = pc.topAnchor.constraint(equalTo: safe.topAnchor)
        // Use safe area for leading so content respects rounded corners in iPhone landscape.
        // In portrait there is no horizontal safe area inset so this is equivalent to
        // view.leadingAnchor on both iPhone and iPad.
        playerLeadingConstraint = pc.leadingAnchor.constraint(equalTo: safe.leadingAnchor)
        playerTrailingConstraint = pc.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        playerToSidebarConstraint = pc.trailingAnchor.constraint(equalTo: sc.leadingAnchor)
        playerAspectConstraint = pc.heightAnchor.constraint(
            equalTo: pc.widthAnchor,
            multiplier: 9.0 / 16.0
        )
        // Not required: in landscape fullscreen the player lives in the window
        // and this view keeps its portrait layout at landscape bounds, where a
        // 16:9 player plus the scroll view below it cannot fit.
        playerAspectConstraint?.priority = UILayoutPriority(999)
        scrollTopToPlayerConstraint = sv.topAnchor.constraint(equalTo: pc.bottomAnchor)
        sidebarTopConstraint = sc.topAnchor.constraint(equalTo: safe.topAnchor)
        // Respect right safe area so sidebar content clears the rounded corner on iPhone landscape.
        sidebarTrailingConstraint = sc.trailingAnchor.constraint(equalTo: safe.trailingAnchor)
        sidebarBottomConstraint = sc.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        sidebarWidthConstraint = sc.widthAnchor.constraint(equalToConstant: 340)
        // Not required: mid-resize (e.g. dragged into a 320pt Slide Over) the
        // landscape layout can still be active at a width the sidebar no longer
        // fits, and UIKit would otherwise break arbitrary cell constraints.
        sidebarWidthConstraint?.priority = UILayoutPriority(999)
        activateScrollConstraints()
    }

    func activateScrollConstraints() {
        let cv = contentView, sv = scrollView
        let cl = sv.contentLayoutGuide, fl = sv.frameLayoutGuide
        NSLayoutConstraint.activate(
            [
                playerTopConstraint, playerLeadingConstraint,
                playerTrailingConstraint, playerAspectConstraint,
                scrollTopToPlayerConstraint, scrollTrailingConstraint,
                // Use safe area for leading to match playerLeadingConstraint so the
                // scroll content aligns with the player edge on iPhone landscape.
                sv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                cv.topAnchor.constraint(equalTo: cl.topAnchor),
                cv.leadingAnchor.constraint(equalTo: cl.leadingAnchor),
                cv.trailingAnchor.constraint(equalTo: cl.trailingAnchor),
                cv.bottomAnchor.constraint(equalTo: cl.bottomAnchor),
                cv.widthAnchor.constraint(equalTo: fl.widthAnchor)
            ].compactMap { $0 }
        )
    }

    func setupPlayerOverlays() {
        let ps = playerSpinner, sl = playerStatusLabel, pc = playerContainer
        [ps, sl].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        ps.startAnimating()
        pc.addSubview(ps)
        sl.text = "player.status.preparing".localized
        sl.textAlignment = .center
        sl.numberOfLines = 0
        sl.font = UIFont.systemFont(ofSize: 14)
        pc.addSubview(sl)
        NSLayoutConstraint.activate([
            ps.centerXAnchor.constraint(equalTo: pc.centerXAnchor),
            ps.centerYAnchor.constraint(equalTo: pc.centerYAnchor, constant: -10),
            sl.topAnchor.constraint(equalTo: ps.bottomAnchor, constant: 14),
            sl.leadingAnchor.constraint(equalTo: pc.leadingAnchor, constant: 24),
            sl.trailingAnchor.constraint(equalTo: pc.trailingAnchor, constant: -24)
        ])
    }

    func setupMetaViews() {
        let cv = contentView
        for item in [titleLabel, metaLabel, descriptionLabel, descriptionButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.numberOfLines = 0
        cv.addSubview(titleLabel)
        metaLabel.font = UIFont.systemFont(ofSize: 13)
        metaLabel.numberOfLines = 0
        cv.addSubview(metaLabel)
        LinkifiedText.configure(descriptionLabel)
        descriptionLabel.font = UIFont.systemFont(ofSize: 13)
        descriptionLabel.isHidden = true
        descriptionLabel.delegate = self
        cv.addSubview(descriptionLabel)
        descriptionButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        descriptionButton.addTarget(self, action: #selector(toggleDescription), for: .touchUpInside)
        descriptionButton.setTitle(
            "player.description.more".localized, for: .normal
        )
        cv.addSubview(descriptionButton)
    }

    func setupChannelViews() {
        let cv = contentView
        for item in [channelAvatarView, channelNameLabel, channelMetaLabel, subscribeButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        channelAvatarView.layer.cornerRadius = 22
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.isUserInteractionEnabled = true
        cv.addSubview(channelAvatarView)
        channelNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        channelNameLabel.isUserInteractionEnabled = true
        cv.addSubview(channelNameLabel)
        channelMetaLabel.font = UIFont.systemFont(ofSize: 12)
        channelMetaLabel.numberOfLines = 2
        cv.addSubview(channelMetaLabel)
        subscribeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        subscribeButton.layer.cornerRadius = 18
        subscribeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        subscribeButton.isEnabled = !OAuthClient.shared.isAnonymous
        let sel = #selector(subscribeButtonTapped)
        subscribeButton.addTarget(self, action: sel, for: .touchUpInside)
        subscribeButton.addTapFeedback()
        cv.addSubview(subscribeButton)
    }

    func setupActionBar() {
        actionBar.axis = .horizontal
        actionBar.distribution = .fillEqually
        actionBar.spacing = 8
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionBar)
        buildActionBarItems()
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        dislikeButton.addTarget(self, action: #selector(dislikeTapped), for: .touchUpInside)
        downloadButton.addTarget(
            self, action: #selector(downloadTapped), for: .touchUpInside
        )
        for item in actionBarItems {
            item.button.addTapFeedback()
        }
    }

    private func buildActionBarItems() {
        for item in actionBarItems {
            actionBar.addArrangedSubview(
                makeActionItem(
                    btn: item.button,
                    iconName: item.icon,
                    staticLabel: item.label,
                    countLabel: item.countLabel
                )
            )
        }
    }

    func makeActionItem(
        btn: UIButton,
        iconName: String,
        staticLabel: String?,
        countLabel: UILabel? = nil
    )
        -> UIStackView {
        if let img = LegacyAssets.image(iconName) {
            let sz = CGSize(width: 22, height: 22)
            let rendered = UIGraphicsImageRenderer(size: sz).image { _ in
                img.draw(in: CGRect(origin: .zero, size: sz))
            }
            btn.setImage(rendered.withRenderingMode(.alwaysTemplate), for: .normal)
        }
        btn.tintColor = ThemeManager.shared.primaryText
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let label = countLabel ?? UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textAlignment = .center
        label.textColor = ThemeManager.shared.secondaryText
        label.text = staticLabel ?? "—"
        label.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [btn, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func setupCommentsSection() {
        let cv = contentView
        for item in [commentsHeaderStack, commentsStackView] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        setupCommentsHeader()
        cv.addSubview(commentsHeaderStack)
        commentsStackView.axis = .vertical
        commentsStackView.spacing = 12
        commentsStackView.isUserInteractionEnabled = true
        commentsStackView.isLayoutMarginsRelativeArrangement = true
        commentsStackView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        setupCommentsPreviewCard()
        // The whole section opens the panel — the header row, the card and
        // the gaps between them, not just the comment text.
        let expandTap = #selector(expandComments)
        for area in [commentsStackView, commentsHeaderStack, commentsLabel] {
            area.isUserInteractionEnabled = true
            area.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: expandTap)
            )
        }
        cv.addSubview(commentsStackView)
        setupCommentsTableView()
        setupCommentsPanel()
        setupQueueBar()
    }

    /// The always-visible "Comments" title above the collapsed preview card
    /// — tap to expand. The panel that opens owns its own title + close.
    private func setupCommentsHeader() {
        commentsLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        commentsLabel.text = "player.comments.title".localized
        commentsHeaderStack.axis = .horizontal
        commentsHeaderStack.alignment = .center
        commentsHeaderStack.addArrangedSubview(commentsLabel)
    }

    private func setupCommentsTableView() {
        let tv = commentsTableView
        tv.register(CommentCell.self, forCellReuseIdentifier: CommentCell.reuseId)
        tv.register(CommentReplyCell.self, forCellReuseIdentifier: CommentReplyCell.reuseId)
        tv.register(CommentStatusCell.self, forCellReuseIdentifier: CommentStatusCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 80
        tv.contentInsetAdjustmentBehavior = .never
        // YouTube separates comments with air, not rules.
        tv.separatorStyle = .none
    }

    /// Pinned to the bottom, above the safe area, over whatever is under it.
    /// Portrait that is the page, so the strip spans the screen. Landscape
    /// puts the comments under the player and the queue's own list in the
    /// sidebar, so a full-width strip lay over the comments — on an iPad wide
    /// enough for both, it was lost there. It spans the sidebar instead, over
    /// the list it belongs to. Hidden until a queue exists.
    private func setupQueueBar() {
        queueBar.isHidden = true
        queueBar.onTap = { [weak self] in
            self?.showQueue()
        }
        let safe = view.safeAreaLayoutGuide
        queueBarSlot.portrait = [
            queueBar.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor, constant: 16
            ),
            queueBar.trailingAnchor.constraint(
                equalTo: safe.trailingAnchor, constant: -16
            )
        ]
        queueBarSlot.landscape = [
            queueBar.leadingAnchor.constraint(
                equalTo: sidebarContainer.leadingAnchor, constant: 16
            ),
            queueBar.trailingAnchor.constraint(
                equalTo: sidebarContainer.trailingAnchor, constant: -16
            )
        ]
        NSLayoutConstraint.activate(queueBarSlot.portrait + [
            queueBar.bottomAnchor.constraint(
                equalTo: safe.bottomAnchor, constant: -8
            ),
            queueBar.heightAnchor.constraint(
                equalToConstant: QueueBarView.height
            )
        ])
    }

    private func setupCommentsPanel() {
        makeSheetDraggable(commentsPanel)
        commentsPanel.onSelectSort = { [weak self] index in
            self?.selectCommentSort(at: index)
        }
        commentsPanel.isHidden = true
    }

    /// Both panels drag by their handle-and-header region; the table view
    /// underneath keeps its own scroll gesture.
    func makeSheetDraggable(_ sheet: PlayerSheetView) {
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleSheetPan)
        )
        sheet.dragRegion.addGestureRecognizer(pan)
    }

    /// A UIStackView does not draw its own `backgroundColor` before iOS 14 —
    /// it is a non-rendering view there, so the card was invisible on the
    /// target device while looking correct on modern iOS. The fill goes on a
    /// plain subview pinned behind the arranged content instead.
    private func setupCommentsPreviewCard() {
        let card = commentsPreviewCard
        commentsStackView.insertSubview(card, at: 0)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 12
        card.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: commentsStackView.topAnchor),
            card.bottomAnchor.constraint(equalTo: commentsStackView.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: commentsStackView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: commentsStackView.trailingAnchor)
        ])
    }

    func setupRelatedCollection() {
        let rv = relatedCollectionView
        rv.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseId)
        rv.register(
            PlaylistSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView
                .elementKindSectionHeader,
            withReuseIdentifier:
            PlaylistSectionHeaderView.reuseIdentifier
        )
        rv.dataSource = self
        rv.delegate = self
        rv.prefetchDataSource = self
        rv.translatesAutoresizingMaskIntoConstraints = false
        rv.isScrollEnabled = false
        // Disable automatic inset adjustment: in portrait the outer scroll view manages
        // all scrolling; in landscape the sidebar is already positioned below the nav bar
        // via safeAreaLayoutGuide, so automatic adjustment would add a redundant top inset
        // that pushes the first related video down or off-screen.
        rv.contentInsetAdjustmentBehavior = .never
        contentView.addSubview(rv)
        relatedSlot.height = rv.heightAnchor.constraint(equalToConstant: 0)
    }

    /// The nav bar does not always contribute its height to
    /// `view.safeAreaInsets` — true for the iOS 26 Liquid Glass bar, and
    /// also on Mac (Designed for iPad), where the top inset is 0 while the
    /// bar still occupies ~50pt.  We measure the gap between the nav-bar
    /// bottom and the raw safe-area top, then push the player container and
    /// the landscape sidebar down so both start below the navigation bar.
    func adjustForFloatingNavBar() {
        // Never measure mid-transition: entering and leaving fullscreen moves
        // the nav bar and this view in separate layout passes, and a reading
        // taken between them is a phantom offset the size of the status bar —
        // it drops the sidebar and everything under the player until the next
        // pass takes it back.
        guard fullscreenSnapshot == nil, !isLeavingFullscreen else {
            return
        }
        guard let navBar = navigationController?.navigationBar,
              !navBar.isHidden
        else {
            applyTopOffset(0)
            return
        }
        let navBarBottom = navBar.convert(
            CGPoint(x: 0, y: navBar.bounds.height),
            to: view
        ).y
        let safeTop = view.safeAreaInsets.top
            - additionalSafeAreaInsets.top
        applyTopOffset(max(0, navBarBottom - safeTop))
    }

    /// The landscape sidebar hangs off the same safe-area top as the player, so
    /// both take the push or the first related card slides under the nav bar.
    private func applyTopOffset(_ offset: CGFloat) {
        if abs(additionalSafeAreaInsets.top) > 0.5 {
            additionalSafeAreaInsets.top = 0
        }
        if abs((playerTopConstraint?.constant ?? 0) - offset) > 0.5 {
            playerTopConstraint?.constant = offset
        }
        if abs((sidebarTopConstraint?.constant ?? 0) - offset) > 0.5 {
            sidebarTopConstraint?.constant = offset
        }
    }
}

struct ActionBarItem {
    let button: UIButton
    let icon: String
    let label: String?
    var countLabel: UILabel?
}
