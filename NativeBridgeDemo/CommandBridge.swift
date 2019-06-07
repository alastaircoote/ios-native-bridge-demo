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
    func wrapper(urlSchemeTask: WKURLSchemeTask) {
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
}


class CommandBridge {
    
    typealias CommandWrapper = (WKURLSchemeTask) -> Void
    
    var commands: [String: CommandWrapper] = [:]
    
    func registerCommand<I:Decodable,O:Encodable>(name: String, _ command: @escaping Command<I,O>.Handler) {
        
        // This looks a little hacky but basically we're converting our generic
        // handler closures into a uniform type that can be added to our commands
        // dictionary
        
        self.commands[name] = Command(command).wrapper
    }
    
    func handleCommand(schemeTask: WKURLSchemeTask) {
        
        // get the command name
        let commandName = schemeTask.request.url!.query!
        
        guard let handler = self.commands[commandName] else {
            // no command with this name? Fail. Shouldn't ever get this
            // because we're specifically adding functions to the webview,
            // but still
            schemeTask.didFailWithError(CommandNotFoundError())
            return
        }
    
        // run the actual handler code
        handler(schemeTask)
        
    }
    
    func getJS() -> String {
        
        // we pass the list of our commands into the JS to then process each
        // of them and add them to existing objects/create new ones
        
        let commands = try! JSONEncoder().encode(Array(self.commands.keys))
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
