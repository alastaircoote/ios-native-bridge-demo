//
//  EventFeed.swift
//  NativeBridgeDemo
//
//  Created by Alastair on 6/7/19.
//  Copyright © 2019 alastair. All rights reserved.
//

import Foundation
import WebKit

class EventFeed {
    let schemeTask:WKURLSchemeTask
    init(schemeTask: WKURLSchemeTask) {
        self.schemeTask = schemeTask
        schemeTask.didReceive(HTTPURLResponse(url: schemeTask.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    
    func dispatch(eventName: String, exampleString: String) throws {
        let json = try JSONEncoder().encode([
            "event": eventName,
            "data": exampleString
        ])
        
        self.schemeTask.didReceive(json + "\n\n".data(using: .utf8)!)
    }
    
    // This code establishes the streaming connection to /feed, decodes
    // events as they arrive and fires them on the window object.
    static let jsCode = """
(function() {

    fetch('/feed', {
      method: "NATIVECOMMAND"
    }).then(function(res) {
      let reader = res.body.getReader();
      let decoder = new TextDecoder("utf-8");

      let chunkHandler = function(chunk) {

        let decodedValue = decoder.decode(chunk.value);

        let separateCommands = decodedValue.split("\\n\\n")
          .map(s => s.trim())
          .filter(s => s !== "");

        separateCommands.forEach(cmd => {
          let json = JSON.parse(cmd);
          let event = new Event(json.event);
          event.data = json.data;
          window.dispatchEvent(event);
        });
    
        // loop infinitely
        reader.read().then(chunkHandler);

      };

      reader.read().then(chunkHandler)

    });

})();
"""
}
