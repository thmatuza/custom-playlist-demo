//
//  ViewController.swift
//  CustomPlaylistDemo
//
//  Created by 松澤 友弘 on 2019/11/22.
//  Copyright © 2019 CyberAgent. All rights reserved.
//

import AVFoundation
import UIKit

// Asset keys
let kPlayableKey = "playable"
// PlayerItem keys
let kStatusKey = "status"
// AVPlayer keys
let kRateKey = "rate"
let kCurrentItemKey = "currentItem"
private var rateObservationContext = 0
private var statusObservationContext = 0
private var currentItemObservationContext = 0

class ViewController: UIViewController {
    private var seekToZeroBeforePlay = false
    private var delegate: CustomPlaylistDelegate?

    @IBOutlet private var playView: PlayerView!
    @IBOutlet private var pauseButton: UIBarButtonItem!
    @IBOutlet private var playButton: UIBarButtonItem!
    @IBOutlet private var toolbar: UIToolbar!

    private var _url: URL?
    private var url: URL? {
        get {
            return _url
        }
        set {
            guard let newValue = newValue else {
                return
            }
            if _url != newValue {
                _url = newValue

                /*
                         Create an asset for inspection of a resource referenced by a given URL.
                         Load the values for the asset keys  "playable".
                         */
                let asset = AVURLAsset(url: newValue, options: nil)
                configDelegates(asset)

                let requestedKeys = [kPlayableKey]

                // Tells the asset to load the values of any of the specified keys that are not already loaded.
                asset.loadValuesAsynchronously(forKeys: requestedKeys, completionHandler: {
                    DispatchQueue.main.async(execute: {
                        self.prepare(toPlay: asset, withKeys: requestedKeys)
                    })
                })
            }
        }
    }
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?

    func setupToolbar() {
        toolbar.items = [playButton]
        syncPlayPauseButtons()
    }

    func initializeView() {
        let origUrl = "https://live.unified-streaming.com/scte35/scte35.isml/.m3u8"
        if let url = URL(string: origUrl.replacingOccurrences(of: httpsScheme, with: customPlaylistScheme)) {
            self.url = url
        }
    }

    override func viewDidLoad() {
        setupToolbar()
        initializeView()
        super.viewDidLoad()
    }

    /*!
     *  Create the asset to play (using the given URL).
     *  Configure the asset properties and callbacks when the asset is ready.
     */
    /*!
     *  Create and setup the custom delegae instance.
     */
    func configDelegates(_ asset: AVURLAsset) {
        //Setup the delegate for custom URL.
        delegate = CustomPlaylistDelegate()
        let resourceLoader = asset.resourceLoader
        resourceLoader.setDelegate(delegate, queue: DispatchQueue(label: "AVARLDelegateDemo loader"))

    }

    /*!
     *  Gets called when the play button is pressed.
     *  Start the playback of the asset and show the pause button.
     */
    @IBAction func issuePlay(_ sender: Any) {
        if seekToZeroBeforePlay {
            seekToZeroBeforePlay = false
            player?.seek(to: .zero)
        }

        player?.play()
        showPauseButton()
    }

    /*!
     *  Gets called when the pause button is pressed.
     *  Stop the play and show the play button.
     */
    @IBAction func issuePause(_ sender: Any) {
        player?.pause()
        showPlayButton()
    }
}

/*!
 *  Interface for the play control buttons.
 *  Play
 *  Pause
 */
extension ViewController {
    func showButton(_ button: UIBarButtonItem) {
        var toolbarItems: [UIBarButtonItem]?
        if let items = toolbar.items {
            toolbarItems = items
        }
        toolbarItems?[0] = button
        toolbar.items = toolbarItems
    }

    func showPlayButton() {
        showButton(playButton)
    }

    func showPauseButton() {
        showButton(pauseButton)
    }

    func syncPlayPauseButtons() {
        //If we are playing, show the pause button otherwise show the play button
        if isPlaying() {
            showPauseButton()
        } else {
            showPlayButton()
        }
    }

    func enablePlayerButtons() {
        playButton.isEnabled = true
        pauseButton.isEnabled = true
    }

    func disablePlayerButtons() {
        playButton.isEnabled = false
        pauseButton.isEnabled = false
    }
}

/*!
 *  Interface for the AVPlayer
 *  - observe the properties
 *  - initialize the play
 *  - play status
 *  - play failed
 *  - play ended
 */
extension ViewController {
    /*!
     *  Called when the value at the specified key path relative
     *  to the given object has changed.
     *  Adjust the movie play and pause button controls when the
     *  player item "status" value changes. Update the movie
     *  scrubber control when the player item is ready to play.
     *  Adjust the movie scrubber control when the player item
     *  "rate" value changes. For updates of the player
     *  "currentItem" property, set the AVPlayer for which the
     *  player layer displays visual output.
     *  NOTE: this method is invoked on the main queue.
     */
    override func observeValue(forKeyPath path: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        // AVPlayerItem "status" property value observer.
        if context == &statusObservationContext {
            syncPlayPauseButtons()

            let status: AVPlayer.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayer.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }

            switch status {
            /* Indicates that the status of the player is not yet known because
                             it has not tried to load new media resources for playback */
            case .unknown:
                disablePlayerButtons()
            case .readyToPlay:
                /* Once the AVPlayerItem becomes ready to play, i.e.
                                 [playerItem status] == AVPlayerItemStatusReadyToPlay,
                                 its duration can be fetched from the item. */

                enablePlayerButtons()
            case .failed:
                let pItem = object as? AVPlayerItem
                assetFailedToPrepare(forPlayback: pItem?.error)
            @unknown default:
                break
            }
        } else if context == &rateObservationContext {
            syncPlayPauseButtons()
        } else if context == &currentItemObservationContext {
            let newPlayerItem = change?[.newKey] as? AVPlayerItem

            // Is the new player item null?
            if newPlayerItem == nil {
                disablePlayerButtons()
            } else {
                // Set the AVPlayer for which the player layer displays visual output.
                playView.player = player

                /* Specifies that the player should preserve the video’s aspect ratio and
                             fit the video within the layer’s bounds. */
                playView.setVideoFillMode(.resizeAspect)

                syncPlayPauseButtons()
            }
        } else {
            super.observeValue(forKeyPath: path, of: object, change: change, context: context)
        }

    }

    /*!
     *  Invoked at the completion of the loading of the values for all keys on the asset that we require.
     *  Checks whether loading was successfull and whether the asset is playable.
     *  If so, sets up an AVPlayerItem and an AVPlayer to play the asset.
     */
    func prepare(toPlay asset: AVURLAsset, withKeys requestedKeys: [AnyHashable]) {
        // Make sure that the value of each key has loaded successfully.
        for thisKey in requestedKeys {
            guard let thisKey = thisKey as? String else {
                continue
            }
            var error: NSError?
            let keyStatus = asset.statusOfValue(forKey: thisKey, error: &error)
            if keyStatus == .failed {
                assetFailedToPrepare(forPlayback: error)
                return
            }
            // If you are also implementing -[AVAsset cancelLoading], add your code here to bail out properly in the case of cancellation.
        }

        // Use the AVAsset playable property to detect whether the asset can be played.
        if !asset.isPlayable {
            // Generate an error describing the failure.
            let localizedDescription =
                NSLocalizedString("Item cannot be played", comment: "Item cannot be played description")
            let localizedFailureReason = NSLocalizedString("The contents of the resource at the specified URL are not playable.", comment: "Item cannot be played failure reason")
            let errorDict = [
                NSLocalizedDescriptionKey: localizedDescription,
                NSLocalizedFailureReasonErrorKey: localizedFailureReason
            ]
            let assetCannotBePlayedError = NSError(domain: Bundle.main.bundleIdentifier ?? "", code: 0, userInfo: errorDict)

            // Display the error to the user.
            assetFailedToPrepare(forPlayback: assetCannotBePlayedError)

            return
        }

        // At this point we're ready to set up for playback of the asset.

        // Stop observing our prior AVPlayerItem, if we have one.
        if playerItem != nil {
            // Remove existing player item key value observers and notifications.

            playerItem?.removeObserver(self, forKeyPath: kStatusKey)

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        }

        // Create a new instance of AVPlayerItem from the now successfully loaded AVAsset.
        playerItem = AVPlayerItem(asset: asset)

        // Observe the player item "status" key to determine when it is ready to play.
        playerItem?.addObserver(self,
                                forKeyPath: kStatusKey, options: [.initial, .new], context: &statusObservationContext)

        /* When the player item has played to its end time we'll toggle
             the movie controller Pause button to be the Play button */
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidReachEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        seekToZeroBeforePlay = false

        // Create new player, if we don't already have one.
        if player == nil {
            // Get a new AVPlayer initialized to play the specified player item.
            self.player = AVPlayer(playerItem: playerItem)

            /* Observe the AVPlayer "currentItem" property to find out when any
                     AVPlayer replaceCurrentItemWithPlayerItem: replacement will/did
                     occur.*/
            player?.addObserver(self,
                                forKeyPath: kCurrentItemKey, options: [.initial, .new], context: &currentItemObservationContext)

            // Observe the AVPlayer "rate" property to update the scrubber control.
            player?.addObserver(self, forKeyPath: kRateKey, options: [.initial, .new], context: &rateObservationContext)
        }

        // Make our new AVPlayerItem the AVPlayer's current item.
        if player?.currentItem != playerItem {
            /* Replace the player item with a new player item. The item replacement occurs
                     asynchronously; observe the currentItem property to find out when the
                     replacement will/did occur*/
            player?.replaceCurrentItem(with: playerItem)

            syncPlayPauseButtons()
        }

    }

    func isPlaying() -> Bool {
        guard let player = player else {
            return false
        }
        return player.rate != 0.0
    }

    /*!
     *  Called when an asset fails to prepare for playback for any of
     *  the following reasons:
     *
     *  1) values of asset keys did not load successfully,
     *  2) the asset keys did load successfully, but the asset is not
     *     playable
     *  3) the item did not become ready to play.
     */
    func assetFailedToPrepare(forPlayback error: Error?) {
        disablePlayerButtons()
        let title = error?.localizedDescription ?? ""
        let message = (error as NSError?)?.localizedFailureReason ?? ""

        // Display the error.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        //We add buttons to the alert controller by creating UIAlertActions:
        let actionOk = UIAlertAction(title: "OK",
            style: .default,
            handler: nil) //You can use a block here to handle a press on this button

        alertController.addAction(actionOk)

        self.present(alertController, animated: true, completion: nil)
    }

    /*!
     *  Called when the player item has played to its end time.
     */
    @objc func playerItemDidReachEnd(_ notification: Notification?) {
        /* After the movie has played to its end time, seek back to time zero
             to play it again. */
        seekToZeroBeforePlay = true
    }
}
