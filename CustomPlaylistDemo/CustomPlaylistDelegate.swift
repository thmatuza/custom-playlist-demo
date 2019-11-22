//
//  CustomPlaylistDelegate.swift
//  CustomPlaylistDemo
//
//  Created by 松澤 友弘 on 2019/11/22.
//  Copyright © 2019 CyberAgent. All rights reserved.
//

import AVFoundation
import UIKit
import mamba

var customPlaylistScheme = "cplp"
var httpsScheme = "https"
private var badRequestErrorCode = 400

class CustomPlaylistDelegate: NSObject, AVAssetResourceLoaderDelegate {
    /*!
     *  is scheme supported
     */
    func schemeSupported(_ scheme: String?) -> Bool {
        if isCustomPlaylistSchemeValid(scheme) {
            return true
        }
        return false
    }

    override init() {
        super.init()
    }

    func reportError(_ loadingRequest: AVAssetResourceLoadingRequest?, withErrorCode error: Int) {
        loadingRequest?.finishLoading(with: NSError(domain: NSURLErrorDomain, code: error, userInfo: nil))
    }

    /*!
     *  AVARLDelegateDemo's implementation of the protocol.
     *  Check the given request for valid schemes:
     *
     * 1) Redirect 2) Custom Play list 3) Custom key
     */
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let scheme = loadingRequest.request.url?.scheme

        if isCustomPlaylistSchemeValid(scheme) {
            DispatchQueue.main.async(execute: {
                self.handleCustomPlaylistRequest(loadingRequest)
            })
            return true
        }

        return false
    }
}

extension CustomPlaylistDelegate {
    func isCustomPlaylistSchemeValid(_ scheme: String?) -> Bool {
        return customPlaylistScheme == scheme
    }

    func toHttps(_ prefix: String, stringRef: MambaStringRef) -> MambaStringRef {
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
     *  2) Generates the play list.
     *  3) Create a reponse with the new URL and report success.
     */
    func handleCustomPlaylistRequest(_ loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = URL(string: loadingRequest.request.url?.absoluteString.replacingOccurrences(of: customPlaylistScheme, with: httpsScheme) ?? "") else {
            reportError(loadingRequest, withErrorCode: badRequestErrorCode)
            return true
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
                                    var prefix = loadingRequest.request.url?.absoluteString
                                    .replacingOccurrences(of: customPlaylistScheme, with: httpsScheme)
                                    let range = (prefix as NSString?)?.range(of: "/", options: .backwards)
                                    prefix = (prefix as NSString?)?.substring(to: range?.location ?? 0)
                                    var playlist = variant
                                    try playlist.transform({ tag in
                                        if tag.tagDescriptor == PantosTag.Location {
                                            return PlaylistTag(
                                                tagDescriptor: PantosTag.Location,
                                                tagData: self.toHttps(prefix ?? "", stringRef: tag.tagData))
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
                                    let masterData = try master.write()
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

        return true
    }
}
