//
// MMMStoredLoadable. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import MMMStoredLoadable
import MMMLoadable
import MMMSnapshotStorage
import XCTest

public final class StoredLoadableTestCase: XCTestCase {
	
	private struct Content: Codable {
		public let identifier: String
		public let title: String
	}
	
	private class Loadable: StoredLoadable<Content> {
		
		public private(set) var content: Content?
		
		public override var isContentsAvailable: Bool { content != nil }
		
		private var timer: Timer?
		public var shouldFail: Bool
		
		public init(
			shouldFail: Bool,
			storage: SingleSnapshotContainer?,
			policy: InvalidationPolicy? = nil,
			populateDirectly: Bool = false
		) {
			self.shouldFail = shouldFail
			
			super.init(storage: storage, policy: policy, populateDirectly: populateDirectly)
		}
		
		deinit {
			timer?.invalidate()
		}
		
		public override func doSync() {
			
			let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
				
				guard let self = self else { return }
				
				guard !self.shouldFail else {
					self.setFailedToSyncWithError(nil)
					
					return
				}
				
				self.setDidSyncSuccessfully(content: .init(identifier: "new", title: "New"))
			}
			
			self.timer = timer
		}
		
		public override func setDidSyncSuccessfully(content: StoredLoadableTestCase.Content) {
			
			self.content = content
			
			super.setDidSyncSuccessfully(content: .init(identifier: "stored", title: "Stored"))
		}
		
		public func reset() {
			self.content = nil
			self.loadableState = .idle
		}
	}
	
	private var observer: MMMLoadableObserver?
	
	public func testBasics() {
		
		let storage = MockSingleSnapshotContainer()
		let loadable = Loadable(shouldFail: false, storage: storage, policy: .custom(1.2))
		
		let expectation = XCTestExpectation(description: "First load")
		
		// First test the initial load, nothing stored yet.
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didSyncSuccessfully:
				
				XCTAssert(loadable.isContentsAvailable)
				XCTAssertEqual(loadable.content!.identifier, "new")
				
				expectation.fulfill()
				
			default:
				break
			}
		}
		
		loadable.syncIfNeeded()
		
		wait(for: [expectation], timeout: 5)
		
		// We reset the loadable, and load again, this time, we expect it to give us the
		// stored value.
		
		loadable.reset()
		
		let expectation2 = XCTestExpectation(description: "Second load")
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didSyncSuccessfully:
				
				XCTAssert(loadable.isContentsAvailable)
				XCTAssertEqual(loadable.content!.identifier, "stored")
				
				expectation2.fulfill()
				
			default:
				break
			}
		}
		
		loadable.syncIfNeeded()
		
		wait(for: [expectation2], timeout: 5)
		
		// Let's check if we needSync after a 1.5 second timer, since our policy of
		// invalidation is 1.2 seconds.
		
		let expectation3 = XCTestExpectation(description: "Third load")
		
		Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
			XCTAssert(loadable.needsSync())
			
			expectation3.fulfill()
		}
		
		wait(for: [expectation3], timeout: 2)
	}
	
	public func testFailed() {
		
		let storage = MockSingleSnapshotContainer()
		let loadable = Loadable(shouldFail: true, storage: storage, policy: .custom(1.2))
		
		let expectation = XCTestExpectation(description: "First load")
		
		// First test the initial load, nothing stored yet.
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didFailToSync:
				
				XCTAssert(!loadable.isContentsAvailable)
				
				expectation.fulfill()
				
			default:
				break
			}
		}
		
		loadable.syncIfNeeded()
		
		wait(for: [expectation], timeout: 5)
		
		// We reset the loadable, and load again, this time, we don't want it to fail.
		loadable.shouldFail = false
		loadable.reset()
		
		let expectation2 = XCTestExpectation(description: "Second load")
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didSyncSuccessfully:
				
				XCTAssert(loadable.isContentsAvailable)
				XCTAssertEqual(loadable.content!.identifier, "new")
				
				expectation2.fulfill()
				
			default:
				break
			}
		}
		
		loadable.syncIfNeeded()
		
		wait(for: [expectation2], timeout: 5)
		
		// Now let's fail the sync again, content should still be available.
		
		let expectation3 = XCTestExpectation(description: "Third load")
		loadable.shouldFail = true
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didFailToSync:
				
				XCTAssert(loadable.isContentsAvailable)
				XCTAssertEqual(loadable.content!.identifier, "new")
				
				expectation3.fulfill()
				
			default:
				break
			}
		}
		
		loadable.sync()
		
		wait(for: [expectation3], timeout: 5)
		
		// Alright, all is good, now let's reset the loadable, and load 'from start'; we
		// keep it at shouldFail; however, it should succeed with storage.
		loadable.reset()
		
		let expectation4 = XCTestExpectation(description: "Fourth load")
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didSyncSuccessfully:
				
				XCTAssert(loadable.isContentsAvailable)
				XCTAssertEqual(loadable.content!.identifier, "stored")
				
				expectation4.fulfill()
				
			default:
				break
			}
		}
		
		loadable.syncIfNeeded()
		
		wait(for: [expectation4], timeout: 5)
	}
	
	public func testExpiredContent() {
	
		let storage = MockSingleSnapshotContainer()
		let loadable = Loadable(
			shouldFail: false,
			storage: storage,
			policy: .custom(0.2),
			populateDirectly: true
		)
		
		let expectation = XCTestExpectation(description: "First load")
		
		// First load some content.
		
		observer = MMMLoadableObserver(loadable: loadable) { _ in
			switch loadable.loadableState {
			case .didSyncSuccessfully:
				
				XCTAssert(loadable.isContentsAvailable)
				
				expectation.fulfill()
				
			default:
				break
			}
		}
		
		loadable.syncIfNeeded()
		
		wait(for: [expectation], timeout: 5)
		
		// We fail the second load, the storage is stil valid, but we want to populate then
		// sync. So we expect the loadable to fail loading, but have content.
		let loadable2 = Loadable(
			shouldFail: true,
			storage: storage,
			policy: .custom(0.2),
			populateDirectly: true
		)
		
		let expectation2 = XCTestExpectation(description: "Second load")
		
		Timer.scheduledTimer(withTimeInterval: 0.21, repeats: false) { _ in
			
			self.observer = MMMLoadableObserver(loadable: loadable2) { _ in
				switch loadable2.loadableState {
				case .didFailToSync:
					
					XCTAssert(loadable.isContentsAvailable)
					
					expectation2.fulfill()
					
				default:
					break
				}
			}
			
			loadable2.syncIfNeeded()
		}
		
		wait(for: [expectation2], timeout: 5)
	}
}
