//
// MMMSnapshotStorage. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import Foundation
import MMMPromisingResult

public final class MockSnapshotStorage: SnapshotStorage {

	public func containerForKey(_ key: String) -> SingleSnapshotContainer {
		MockSingleSnapshotContainer(key: key)
	}
	
	public func removeContainerForKey(_ key: String) -> Bool { true }
}

/// To mock a snapshot container by storing the last saved value in memory.
public final class MockSingleSnapshotContainer: SingleSnapshotContainer {

	public let key: String

	public init(key: String = "") {
		self.key = key
	}

	/// The last saved snapshot, if any.
	/// The owner can reset it or set to something weird to cause a loading error.
	/// Note that we don't even have to encode/decode here, could just store the value as is.
	public var snapshot: Data?

	public func loadSync<T: Decodable>(_ type: T.Type) throws -> T? {
		if let snapshot = self.snapshot {
			return try JSONDecoder().decode(type, from: snapshot)
		} else {
			return nil
		}
	}

	public func load<T: Decodable>(_ type: T.Type) -> PromisingResult<T?, Error> {
		let sink = PromisingResultSink<T?, Error>(queue: .main)
		// Let's do this on a queue to make sure async loads are tested.
		DispatchQueue.main.async {
			do {
				sink.push(.success(try self.loadSync(type)))
			} catch {
				sink.push(.failure(error))
			}
		}
		return sink.drain
	}

	public func save<T: Encodable>(_ snapshot: T) {
		// It's a mock one, inability to encode must be flagged asap.
		self.snapshot = try! JSONEncoder().encode(snapshot)
	}
	
	public func clean() -> Promising<Bool> {
	
		let sink = PromisingResultSink<Bool, Error>(queue: .main)
		// Let's do this on a queue to make sure async loads are tested.
		DispatchQueue.main.async {
			sink.push(.success(self.cleanSync()))
		}
		return sink.drain
	}
	
	public func cleanSync() -> Bool {
		snapshot = nil
		return true
	}
}
