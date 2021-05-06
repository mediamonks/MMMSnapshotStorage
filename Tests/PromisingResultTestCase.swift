//
// Avianca iOS App.
// Copyright (C) 2020 Avianca S.A. All rights reserved.
// Developed for Avianca by MediaMonks B.V.
//

@testable import MMMPromisingResult
import XCTest

class PromisingResultTestCase: XCTestCase {

	private var sink: PromisingResultSink<Int, Error>!
	private var result: PromisingResult<Int, Error>!
	private var completedExpectation: XCTestExpectation!

	override func setUp() {
		super.setUp()
		self.sink = .init()
		self.result = sink.drain
		self.completedExpectation = expectation(description: "Result has been completed")
		completedExpectation.assertForOverFulfill = true
	}

	func testForward() {
		_ = result.completion {
			XCTAssertEqual(try! $0.get(), 123)
			self.completedExpectation.fulfill()
		}
		sink.push(.success(123))
		wait(for: [completedExpectation], timeout: 1)
	}

	func testBackwards() {
		sink.push(.success(123))
		_ = result.completion {
			XCTAssertEqual(try! $0.get(), 123)
			self.completedExpectation.fulfill()
		}
		wait(for: [completedExpectation], timeout: 1)
	}

	func testTransform() {
		_ = result
			.transform { $0.map { String(describing: $0) } }
			.completion {
				XCTAssertEqual(try! $0.get(), "123")
				self.completedExpectation.fulfill()
			}
		sink.push(.success(123))
		wait(for: [completedExpectation], timeout: 1)
	}
}
