//
//  ShelfViewController.swift
//  WWDC
//
//  Created by Guilherme Rambo on 22/04/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Cocoa
import Combine
import CoreMedia
import PlayerUI
import AVFoundation

protocol ShelfViewControllerDelegate: AnyObject {
    func shelfViewControllerDidSelectPlay(_ controller: ShelfViewController)
    func shelfViewController(_ controller: ShelfViewController, didBeginClipSharingWithHost hostView: NSView)
    func suggestedBeginTimeForClipSharingInShelfViewController(_ controller: ShelfViewController) -> CMTime?
    func shelfViewControllerDidEndClipSharing(_ controller: ShelfViewController)
}

final class ShelfViewController: NSViewController, PUIPlayerViewDetachedStatusPresenter {

    weak var delegate: ShelfViewControllerDelegate?

    private lazy var cancellables: Set<AnyCancellable> = []

    var viewModel: SessionViewModel? {
        didSet {
            updateBindings()
        }
    }

    lazy var shelfView: ShelfView = {
        let v = ShelfView()

        v.translatesAutoresizingMaskIntoConstraints = false

        return v
    }()

    lazy var playerContainer: NSView = {
        let v = NSView()

        v.translatesAutoresizingMaskIntoConstraints = false

        return v
    }()

    lazy var playButton: VibrantButton = {
        let b = VibrantButton(frame: .zero)

        b.title = "Play"
        b.translatesAutoresizingMaskIntoConstraints = false
        b.target = self
        b.action = #selector(play)
        b.isHidden = true

        return b
    }()

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: MainWindowController.defaultRect.width - 300, height: MainWindowController.defaultRect.height / 2))
        view.wantsLayer = true

        view.addSubview(shelfView)
        shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        shelfView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        shelfView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        view.addSubview(playButton)
        playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        playButton.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        view.addSubview(playerContainer)
        playerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        playerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        playerContainer.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        playerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateBindings()
    }

    override func viewWillLayout() {
        updateVideoLayoutGuide()

        super.viewWillLayout()
    }

    private weak var currentImageDownloadOperation: Operation?

    private func updateBindings() {
        cancellables = []

        guard let viewModel = viewModel else {
            shelfView.image = nil
            return
        }

        viewModel.rxCanBePlayed.toggled().replaceError(with: true).driveUI(\.isHidden, on: playButton).store(in: &cancellables)

        viewModel.rxImageUrl.replaceErrorWithEmpty().sink { [weak self] imageUrl in
            self?.currentImageDownloadOperation?.cancel()
            self?.currentImageDownloadOperation = nil

            guard let imageUrl = imageUrl else {
                self?.shelfView.image = #imageLiteral(resourceName: "noimage")
                return
            }

            self?.currentImageDownloadOperation = ImageDownloadCenter.shared.downloadImage(from: imageUrl, thumbnailHeight: Constants.thumbnailHeight) { url, result in
                self?.shelfView.image = result.original
            }
        }
        .store(in: &cancellables)
    }

    @objc func play(_ sender: Any?) {
        self.delegate?.shelfViewControllerDidSelectPlay(self)
    }

    private var sharingController: ClipSharingViewController?

    func showClipUI() {
        guard let session = viewModel?.session else { return }
        guard let url = DownloadManager.shared.downloadedFileURL(for: session) else { return }

        let subtitle = session.event.first?.name ?? "Apple Developer"

        let suggestedTime = delegate?.suggestedBeginTimeForClipSharingInShelfViewController(self)

        let controller = ClipSharingViewController(
            with: url,
            initialBeginTime: suggestedTime,
            title: session.title,
            subtitle: subtitle
        )

        addChild(controller)
        controller.view.autoresizingMask = [.width, .height]
        controller.view.frame = playerContainer.bounds
        playerContainer.addSubview(controller.view)

        sharingController = controller

        delegate?.shelfViewController(self, didBeginClipSharingWithHost: controller.playerView)

        controller.completionHandler = { [weak self] in
            guard let self = self else { return }

            self.delegate?.shelfViewControllerDidEndClipSharing(self)
        }
    }

    // MARK: - Detached Playback Status

    private weak var detachedPlayer: AVPlayer?

    func presentDetachedStatus(_ status: DetachedPlaybackStatus, for playerView: PUIPlayerView) {
        guard let player = playerView.player else { return }

        self.detachedPlayer = player

        installDetachedStatusControllerIfNeeded()

        detachedStatusController.status = status
        detachedStatusController.show()
    }

    func dismissDetachedStatus(_ status: DetachedPlaybackStatus, for playerView: PUIPlayerView) {
        guard detachedStatusController.parent != nil else { return }

        detachedStatusController.hide()

        self.detachedPlayer = nil
    }

    private lazy var detachedStatusController = PUIDetachedPlaybackStatusViewController()

    private func installDetachedStatusControllerIfNeeded() {
        guard detachedStatusController.parent == nil else { return }

        updateVideoLayoutGuide()

        addChild(detachedStatusController)

        let statusView = detachedStatusController.view
        statusView.wantsLayer = true
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusView, positioned: .above, relativeTo: view.subviews.first)

        statusView.layer?.zPosition = 9

        NSLayoutConstraint.activate([
            statusView.leadingAnchor.constraint(equalTo: videoLayoutGuide.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: videoLayoutGuide.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: videoLayoutGuide.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: videoLayoutGuide.bottomAnchor)
        ])
    }

    private lazy var videoLayoutGuide = NSLayoutGuide()
    private lazy var videoLayoutGuideConstraints = [NSLayoutConstraint]()

    private func updateVideoLayoutGuide() {
        guard let detachedPlayer else { return }

        detachedPlayer.updateLayout(guide: videoLayoutGuide, container: view, constraints: &videoLayoutGuideConstraints)
    }

}
