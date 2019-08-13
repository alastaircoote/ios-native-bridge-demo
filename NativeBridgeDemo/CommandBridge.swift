//
//  CommandBridge.swift
//  NativeBridgeDemo
//
//  Created by Alastair on 6/7/19.
//  Copyright © 2019 alastair. All rights reserved.
//

import Foundation
import WebKit

class CommandNotFoundError : Error {}
class IncorrectInputError : Error {}

enum Result<ResultType> {
    case success(ResultType)
    case failure(Error)
}

class Command<Input: Decodable, Output: Encodable> {
    
    typealias Handler = (Input, (Result<Output>) -> Void) -> Void
    
    let handler: Handler
    
    init(_ handler: @escaping Handler) {
        self.handler = handler
    }
    
    
    /// Take the JSON input, convert it to our input type (or fail), run the handler
    /// and either convert the output type to JSON or fail with the error provided
    func httpWrapper(urlSchemeTask: WKURLSchemeTask) {
        do {
            let input = try JSONDecoder().decode(Input.self, from: urlSchemeTask.request.httpBody!)
            handler(input) { result in
                switch result {
                case .success(let successValue):
                    urlSchemeTask.didReceive(HTTPURLResponse(url: urlSchemeTask.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                    urlSchemeTask.didReceive(try! JSONEncoder().encode(successValue))
                    urlSchemeTask.didFinish()
                case .failure(let errorValue):
                    urlSchemeTask.didFailWithError(errorValue)
                }
                
            }
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }
    
    func scriptMessageWrapper(scriptMessage: WKScriptMessage) {
        let body = scriptMessage.body as! [String: Any]
        let returnID = body["resultID"] as! Int
        do {
            let input = try JSONDecoder().decode(Input.self, from: (body["payload"] as! String).data(using: .utf8)!)
            handler(input) { result in
                switch result {
                case .success(let successValue):
                    let encoded = try! JSONEncoder().encode(successValue)
                    let successScript = "window.receiveResult(true,\(returnID),\(String(data: encoded, encoding: .utf8)!))"
                    scriptMessage.webView!.evaluateJavaScript(successScript, completionHandler: nil)
                case .failure(let errorValue):
                    scriptMessage.webView!.evaluateJavaScript("window.recieveResult(false, \(returnID),'\(String(describing:errorValue))')", completionHandler: nil)
                }
                }
            
        } catch {
            scriptMessage.webView!.evaluateJavaScript("window.receiveResult(false, \(returnID),'\(String(describing:error))')", completionHandler: nil)
        }
    }
}


class CommandBridge {
    
    typealias HTTPCommandWrapper = (WKURLSchemeTask) -> Void
    typealias ScriptMessageCommandWrapper = (WKScriptMessage) -> Void
    
    var httpCommands: [String: HTTPCommandWrapper] = [:]
    var scriptMessageCommands: [String: ScriptMessageCommandWrapper] = [:]
    
    func registerCommand<I:Decodable,O:Encodable>(name: String, _ command: @escaping Command<I,O>.Handler) {
        
        // This looks a little hacky but basically we're converting our generic
        // handler closures into a uniform type that can be added to our commands
        // dictionary
        
        let command = Command(command)
        
        self.httpCommands[name] = command.httpWrapper
        self.scriptMessageCommands[name] = command.scriptMessageWrapper
    }
    
    func handleCommandBy(urlSchemeTask: WKURLSchemeTask) {
        
        // get the command name
        let commandName = urlSchemeTask.request.url!.query!
        
        guard let handler = self.httpCommands[commandName] else {
            // no command with this name? Fail. Shouldn't ever get this
            // because we're specifically adding functions to the webview,
            // but still
            urlSchemeTask.didFailWithError(CommandNotFoundError())
            return
        }
    
        // run the actual handler code
        handler(urlSchemeTask)
        
    }
    
    func handleCommandBy(scriptMessage: WKScriptMessage) {
        let body = scriptMessage.body as! [String: Any]
        let commandName = body["command"] as! String
        
        guard let handler = self.scriptMessageCommands[commandName] else {
            NSLog("No command for this")
            return
        }
        
        handler(scriptMessage)
        
    }
    
    func getJSForScriptMessageAPI() -> String {
        let commands = try! JSONEncoder().encode(Array(self.httpCommands.keys))
        let jsonString = String(data: commands, encoding: .utf8)!
        
        return """
            const commands = \(jsonString);
            let latestID = 0;
            let callbacks = {};
        
            function mapChainToScriptMessageCall() {
                let argumentsArray = Array.from(arguments);
                latestID++;
        
                window.webkit.messageHandlers.bridge.postMessage({
                    resultID: latestID,
                    command: this.toString(),
                    payload: JSON.stringify(argumentsArray[0])
                });
        
                return new Promise(function(fulfill,reject) {
                    callbacks[latestID] = { fulfill,reject };
                });
        
            }
        
            commands.forEach(cmd => {
                let split = cmd.split(".");
                let funcName = split.pop();
                let baseObject = window;
        
                split.forEach(property => {
                    let newObject = baseObject[property];
                    if (!newObject) {
                        newObject = {};
                        baseObject[property] = newObject;
                    }
                    baseObject = newObject;
                    })
        
                baseObject[funcName] = mapChainToScriptMessageCall.bind(cmd);
        
            });
        
        window.receiveResult = function(success, id, payload) {
            let callback = callbacks[id];
            delete callbacks[id];
            if (success === false) {
                let error = new Error(payload);
                callback.reject(error);
            } else {
                callback.fulfill(payload);
            }
        }
    """
        
    }
    
    func getJSForHTTPAPI() -> String {
        
        // we pass the list of our commands into the JS to then process each
        // of them and add them to existing objects/create new ones
        
        let commands = try! JSONEncoder().encode(Array(self.httpCommands.keys))
        let jsonString = String(data: commands, encoding: .utf8)!
        
        return """
            const commands = \(jsonString);

            function mapChainToHTTPCall() {
                let argumentsArray = Array.from(arguments);
                return (
                    fetch("/command?" + this, {
                        method: "NATIVECOMMAND",
                        // Send our arguments as a JSON-encoded array
                        body: JSON.stringify(argumentsArray[0]),
                    })
                    // Then we take a JSON-encoded response, decode it and return
                    .then(res => res.json())
                );
            }
        
            commands.forEach(cmd => {
                let split = cmd.split(".");
                let funcName = split.pop();
                let baseObject = window;
        
                split.forEach(property => {
                    let newObject = baseObject[property];
                    if (!newObject) {
                        newObject = {};
                        baseObject[property] = newObject;
                    }
                    baseObject = newObject;
                })
        
                baseObject[funcName] = mapChainToHTTPCall.bind(cmd);
        
            });

        """
        
    }
    
}
