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
    let handler:ExampleHandler
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        let config = WKWebViewConfiguration()
        self.handler = ExampleHandler(config)
    
        self.webview = WKWebView(frame: CGRect(x: 0, y: 0, width: 0, height: 0), configuration: config)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.view = self.webview
        self.webview.load(URLRequest(url: URL(string: "proxy://alike-quicksand.glitch.me/")!))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}


/// This is the format the webview will send into our command handler
struct ExampleInput : Decodable {
    let exampleNumber: Int
}

/// This is the format we'll send back
struct ExampleResult : Encodable {
    let resultNumber : Int
}

/// The example event we'll dispatch in the timer
struct TestEvent: JSEvent {
    let name = "test-event"
    let attachedString: String
}

class ExampleHandler : NSObject, WKURLSchemeHandler  {
    
    let commandBridge = CommandBridge()
    
    init(_ config: WKWebViewConfiguration) {
        super.init()
        
        // Register our example command. All we're going to do is return whatever number
        // the webview sent us multiplied by 100. Notice that we're specifying the input type,
        // but can infer the result type by the way we use callback():
        
        commandBridge.registerCommand(name: "navigator.exampleNativeBridge.test") { (input: ExampleInput, callback) in
            callback(
                .success(
                    ExampleResult(resultNumber: input.exampleNumber * 100)
                )
            )
        }
        
        
        // intercept all requests sent to proxy://
        config.setURLSchemeHandler(self, forURLScheme: "proxy")
        
        // Add the code that'll fire the event feed request
        config.userContentController.addUserScript(WKUserScript(source: EventFeed.jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        
        // Add the code that'll attach our custom events
        config.userContentController.addUserScript(WKUserScript(source: self.commandBridge.getJS(), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        

    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        
        // We use a special HTTP method to indicate when we're sending a native
        // command request.
        
        if urlSchemeTask.request.httpMethod == "NATIVECOMMAND" {
            return handleNativeCommand(urlSchemeTask: urlSchemeTask)
        }
        
        // Otherwise we're going to proxy to a remote URL (loading a local file
        // isn't demoed here, but you can imagine how it would work)
        
        return proxyRequest(urlSchemeTask: urlSchemeTask)
    }
    
    var feed: EventFeed? = nil
    
    // ignore this, just used for demo purposes:
    var timer: Timer? = nil
    
    func handleNativeCommand(urlSchemeTask: WKURLSchemeTask) {
        
        if urlSchemeTask.request.url?.path == "/feed" {
            
            // this request is made by the EventFeed.jsCode execution, which
            // streams the events we send it into JS events
            
            let feed = EventFeed(schemeTask: urlSchemeTask)
            self.feed = feed
            
            // For our demo we'll dispatch an event every three seconds
            self.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                try! self?.feed?.dispatch(event: TestEvent(attachedString: Date().description))
            }
            
        } else {
            self.commandBridge.handleCommand(schemeTask: urlSchemeTask)
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
        
        /// Also, an ObjC exception is thrown if you try to send data into a task that's
        /// already finished. So we need to make sure we know when one has been stopped.
        
        
        if urlSchemeTask.request.url?.path == "/feed" {
            // But we need to close the feed otherwise it WILL fail on reload, since it's
            // an active connection.
            self.feed = nil
            self.timer?.invalidate()
            self.timer = nil
        }
    }
    
    
}
