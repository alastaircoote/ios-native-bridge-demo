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
        
        var req = urlSchemeTask.request
        var urlComponents = URLComponents(url: req.url!, resolvingAgainstBaseURL: true)!
        urlComponents.scheme = "https"
        req.url = urlComponents.url!
        
        
        URLSession.shared.dataTask(with: req) { (data, response, error) in
            if let err = error {
              return urlSchemeTask.didFailWithError(err)
            }
            // we know response and data exist for the purposes of this demo
            urlSchemeTask.didReceive(response!)
            urlSchemeTask.didReceive(data!)
            urlSchemeTask.didFinish()
        }.resume()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // we'd handle intercepting currently running tasks if we were doing
        // this for real
    }
    
    
}
