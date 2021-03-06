//
// MMMSnapshotStorage. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

@testable import MMMSnapshotStorage
import XCTest

class FileBaseSnapshotStorageTestCase: XCTestCase {

	private struct Snapshot: Codable {
		var a: Int
	}

	func testBasics() {

		let directory = "Tests-\(Date.timeIntervalSinceReferenceDate)"
		let storage: SnapshotStorage = FileBasedSnapshotStorage(libraryDirectory: directory)

		let key1 = "1"
		let key2 = "2/%🍐" // To check that things are escaped.

		do {
			let container1 = storage.containerForKey(key1)
			container1.save(Snapshot(a: 1234))
			container1.save(Snapshot(a: 6543))
			container1.save(Snapshot(a: 1))

			let container2 = storage.containerForKey(key2)
			container2.save(Snapshot(a: 2))
		}

		do {
			guard let value2 = try! storage.containerForKey(key2).loadSync(Snapshot.self) else {
				XCTFail("Expected the snapshot to exist")
				return
			}
			XCTAssertEqual(value2.a, 2)

			guard let value1 = try! storage.containerForKey(key1).loadSync(Snapshot.self) else {
				XCTFail("Expected the snapshot to exist")
				return
			}
			XCTAssertEqual(value1.a, 1)
		}
	}

	func testClean() {

		let directory = "Tests-\(Date.timeIntervalSinceReferenceDate)"
		let storage: SnapshotStorage = FileBasedSnapshotStorage(libraryDirectory: directory)

		let key1 = "1"
		let key2 = "2/%🍐" // To check that things are escaped.

		do {
			let container1 = storage.containerForKey(key1)
			container1.save(Snapshot(a: 1234))
			container1.save(Snapshot(a: 6543))
			container1.save(Snapshot(a: 1))

			let container2 = storage.containerForKey(key2)
			container2.save(Snapshot(a: 2))
			container2.clean()
		}

		do {
			XCTAssertNil(try! storage.containerForKey(key2).loadSync(Snapshot.self))

			guard let value1 = try! storage.containerForKey(key1).loadSync(Snapshot.self) else {
				XCTFail("Expected the snapshot to exist")
				return
			}
			XCTAssertEqual(value1.a, 1)
		}
		
		do {
			storage.removeContainerForKey(key1)
			
			XCTAssertNil(try! storage.containerForKey(key1).loadSync(Snapshot.self))
		}
		
		do {
			let container2 = storage.containerForKey(key2)
			container2.save(Snapshot(a: 1))
			container2.clean()
			container2.save(Snapshot(a: 2))
		}
		
		do {
			guard let value2 = try! storage.containerForKey(key2).loadSync(Snapshot.self) else {
				XCTFail("Expected the snapshot to exist")
				return
			}
			XCTAssertEqual(value2.a, 2)
		}
	}
}
