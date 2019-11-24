//
//  CustomPlaylistDelegate.swift
//  CustomPlaylistDemo
//
//  Created by Tomohiro Matsuzawa on 2019/11/22.
//  Copyright © 2019 CyberAgent. All rights reserved.
//

import AVFoundation
import UIKit
import mamba

let customPlaylistScheme = "cplp"
let httpsScheme = "https"
private let badRequestErrorCode = 400

class CustomPlaylistDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private func reportError(_ loadingRequest: AVAssetResourceLoadingRequest, withErrorCode error: Int) {
        loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: error, userInfo: nil))
    }

    /*!
     *  AVARLDelegateDemo's implementation of the protocol.
     *  Check the given request for valid schemes:
     */
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let scheme = loadingRequest.request.url?.scheme else {
            return false
        }

        if isCustomPlaylistSchemeValid(scheme) {
            DispatchQueue.main.async(execute: {
                self.handleCustomPlaylistRequest(loadingRequest)
            })
            return true
        }

        return false
    }
}

private extension CustomPlaylistDelegate {
    func isCustomPlaylistSchemeValid(_ scheme: String) -> Bool {
        return customPlaylistScheme == scheme
    }

    func toAbsolutePath(_ prefix: String, stringRef: MambaStringRef) -> MambaStringRef {
        var string = stringRef.stringValue()
        if !string.starts(with: "http") {
            string = prefix + "/" + string
        }
        return MambaStringRef(string: string)
    }

    /*!
     *  Handles the custom play list scheme:
     *
     *  1) Verifies its a custom playlist request, otherwise report an error.
     *  2) Receive the play list from server.
     *  3) Manipulate manifest and report success.
     */
    func handleCustomPlaylistRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = URL(string: loadingRequest.request.url?.absoluteString.replacingOccurrences(of: customPlaylistScheme, with: httpsScheme) ?? "") else {
            reportError(loadingRequest, withErrorCode: badRequestErrorCode)
            return
        }
        let request = URLRequest(url: url)
        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, _, error in
            guard error == nil, let data = data else {
                self.reportError(loadingRequest, withErrorCode: badRequestErrorCode)
                return
            }

            let parser = PlaylistParser()

            parser.parse(playlistData: data,
                         url: url,
                         callback: { result in
                            switch result {
                            case .parsedVariant(let variant):
                                do {
                                    var prefix = url.absoluteString
                                    if let index = prefix.lastIndex(of: "/") {
                                        prefix = String(prefix[..<index])
                                    }
                                    var playlist = variant
                                    // manipulate media playlist here

                                    // need to convert to absolute path with httpsScheme
                                    // because relative path is resolved with customPlaylistScheme
                                    try playlist.transform({ tag in
                                        if tag.tagDescriptor == PantosTag.Location {
                                            return PlaylistTag(
                                                tagDescriptor: PantosTag.Location,
                                                tagData: self.toAbsolutePath(prefix, stringRef: tag.tagData))
                                        }
                                        return tag
                                    })
                                    let variantData = try playlist.write()
                                    loadingRequest.dataRequest?.respond(with: variantData)
                                    loadingRequest.finishLoading()
                                } catch {
                                    self.reportError(loadingRequest, withErrorCode: badRequestErrorCode)
                                }
                            case .parsedMaster(let master):
                                do {
                                    var playlist = master
                                    // manipulate master playlist here

                                    let masterData = try playlist.write()
                                    loadingRequest.dataRequest?.respond(with: masterData)
                                    loadingRequest.finishLoading()
                                } catch {
                                    self.reportError(loadingRequest, withErrorCode: badRequestErrorCode)
                                }
                            case .parseError(let error):
                                // handle the ParserError
                                print(error)
                                self.reportError(loadingRequest, withErrorCode: badRequestErrorCode)
                            }
            })
        })

        task.resume()

        return
    }
}
