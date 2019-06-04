//
//  ViewController.swift
//  NativeBridgeDemo
//
//  Created by Alastair on 6/3/19.
//  Copyright © 2019 alastair. All rights reserved.
//

import UIKit
import WebKit

class ViewController: UIViewController {
    
    let webview:WKWebView
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(Handler(), forURLScheme: "proxy")
        self.webview = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: config)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.view = self.webview
        self.webview.load(URLRequest(url: URL(string: "proxy://alike-quicksand.glitch.me/")!))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
    }


}

class CommandNotFoundError : Error {}

class Handler : NSObject, WKURLSchemeHandler  {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        if urlSchemeTask.request.httpMethod == "NATIVECOMMAND" {
            return handleNativeCommand(urlSchemeTask: urlSchemeTask)
        }
        return proxyRequest(urlSchemeTask: urlSchemeTask)
    }
    
    func handleNativeCommand(urlSchemeTask: WKURLSchemeTask) {
        if urlSchemeTask.request.url?.path == "/navigator/exampleNativeBridge/test" {
            
            do {
                let result = try JSONEncoder().encode([
                    "exampleString": Date().description
                ])
                
                urlSchemeTask.didReceive(HTTPURLResponse(url: urlSchemeTask.request.url!, statusCode: 200, httpVersion: nil, headerFields: [
                    "content-type": "application/json"
                    ])!)
                urlSchemeTask.didReceive(result)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
            
        } else {
            urlSchemeTask.didFailWithError(CommandNotFoundError())
        }
    }
    
    func proxyRequest(urlSchemeTask: WKURLSchemeTask) {
        
        // The incoming request is for proxy://whatever, let's rewrite it
        // to be an https:// URL.
        
        /// TODO: a production version of this would also rewrite the HTTP headers
        /// for referrer, origin, etc to also be https://
        
        var req = urlSchemeTask.request
        var urlComponents = URLComponents(url: req.url!, resolvingAgainstBaseURL: true)!
        urlComponents.scheme = "https"
        req.url = urlComponents.url!
        
        /// TODO: a production version of this wouldn't download the entire response before
        /// sending it to the webview. Imagine we're downloading a multi-MB video - it should
        /// be passed through as data arrives (you can call urlSchemeTask.didReceive(Data)
        /// as many times as you want), perhaps through a URLSessionDataDelegate
        
        URLSession.shared.dataTask(with: req) { (data, response, error) in
            if let err = error {
              return urlSchemeTask.didFailWithError(err)
            }
            
            /// TODO: this response URL needs to be rewritten back to proxy://. For the purposes
            /// of this demo it works, but any subsequent resource loads (CSS, JS, etc)
            /// will go straight to https:// when we want them to go to proxy://
            
            // we know response and data exist for the purposes of this demo so just using !
            // everywhere
            
            urlSchemeTask.didReceive(response!)
            urlSchemeTask.didReceive(data!)
            urlSchemeTask.didFinish()
        }.resume()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        /// TODO: a production version of this would halt ongoing downloads when the webview
        /// requests it. Again, imagine the multi-MB video. If the user stops the video the
        /// webview will cancel the in-progress download. So we'd need to keep track of
        /// active WKURLSchemeTasks and their corresponding URLSessionDataTasks
    }
    
    
}
