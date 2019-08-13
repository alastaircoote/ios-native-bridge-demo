//
//  NativeBridgeDemoTests.swift
//  NativeBridgeDemoTests
//
//  Created by Alastair on 8/13/19.
//  Copyright © 2019 alastair. All rights reserved.
//

import XCTest
import WebKit
@testable import NativeBridgeDemo

struct TestPayload : Codable {
    let number: Int
}

class NativeBridgeDemoTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func doTest(type: BridgeType) {
        let config = WKWebViewConfiguration()
        let handler = ExampleHandler(config)
        
        let expect = expectation(description: "completes")
        
        handler.commandBridge.registerCommand(name: "navigator.test.one", { (input: TestPayload, callback) in
            callback(.success(TestPayload(number: input.number * 10)))
        })
        
        handler.commandBridge.registerCommand(name: "navigator.test.two", { (input: TestPayload, callback: (Result<TestPayload>) -> Void) in
            callback(.success(TestPayload(number: 0)))
            expect.fulfill()
            return
        })
        
        handler.injectJS(type: type)
        
        let webview = WKWebView(frame: CGRect(x: 0, y: 0, width: 0, height: 0), configuration: config)
        
        webview.loadHTMLString("""
                <script>navigator.test.one({number: 5})
                .then(function(result) {
                    navigator.test.two({number: result.number * 10})
                })</script>
            """, baseURL: URL(string: "proxy://www.example.com")!)
        
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testScriptMessageAPI() {
        measure {
            doTest(type: .scriptMessageAPI)
        }
    }
    
    func testHTTPAPI() {
        measure {
            doTest(type: .httpAPI)
        }
    }


}
