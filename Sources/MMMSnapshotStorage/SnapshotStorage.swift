//
// MMMSnapshotStorage. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import Foundation

#if SWIFT_PACKAGE
import MMMPromisingResult
#endif

/// Support for simple snapshot-based persistence.
///
/// Each model that needs to store its state is provided (by its owner) with a container.
/// The container is then used to save or load the state as a single "snapshot".
public protocol SnapshotStorage {

	/// Returns a container prepared to load/store snapshots of a single object.
	///
	/// The container is passed to the corresponding object by its owner.
	/// The way the keys are assigned to each object is determined by the owner as well.
	func containerForKey(_ key: String) -> SingleSnapshotContainer
	
	/// Remove a container (do clean up) for a given key, synchronously.
	@discardableResult
	func removeContainerForKey(_ key: String) -> Bool
}

/// Something that can hold a single "snapshot" of an object. This is to be passed to models that need to be
/// persisted in a simple load/save fashion.
public protocol SingleSnapshotContainer {

	/// Asynchronously loads a snapshot from the container. A `nil` is returned if no previous state was stored.
	func load<T: Decodable>(_ type: T.Type) -> Promising<T?>

	/// The synchronous version of `load()`.
	/// The latter is preferred for large object, but this one might be easier to use in the existing code.
	func loadSync<T: Decodable>(_ type: T.Type) throws -> T?

	/// Schedules to save the given snapshot replacing anything previously saved.
	/// Note that this might be performed asynchronously and lazily (e.g. only when the app goes to background),
	/// so the snapshot should be able to encode itself on a different queue.
	func save<T: Encodable>(_ snapshot: T)
	
	/// Clean this container (e.g. remove contents), but keep it alive for later use. If you don't need to keep the container
	/// around, use `SnapshotStorage.removeContainerForKey(_:)` instead.
	@discardableResult
	func clean() -> Promising<Bool>
	
	/// The synchronous version of `clean()`.
	@discardableResult
	func cleanSync() ->  Bool
}
