//
//  EventFeed.swift
//  NativeBridgeDemo
//
//  Created by Alastair on 6/7/19.
//  Copyright © 2019 alastair. All rights reserved.
//

import Foundation
import WebKit

protocol JSEvent : Encodable {
    var name: String {get}
}

class EventFeed {
    let schemeTask:WKURLSchemeTask
    init(schemeTask: WKURLSchemeTask) {
        self.schemeTask = schemeTask
        
        // Send a dummy initial response back - there isn't really anything important
        // in here, except that if we don't send a 200 response the browser might close it
        schemeTask.didReceive(HTTPURLResponse(url: schemeTask.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    
    func dispatch<EventType:JSEvent>(event: EventType) throws {
        let json = try JSONEncoder().encode(event)
        
        // putting in \n\n because it's possible (though not documented) that WKWebView
        // might conbine multiple didReceive() calls into one fetch body read. So on the
        // JS side we split again by \n\n to make sure we're not missing anything.
        
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
          let event = new Event(json.name);
          Object.keys(json).forEach(key => {
            if (key == "name") return;
            event[key] = json[key];
          });
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
