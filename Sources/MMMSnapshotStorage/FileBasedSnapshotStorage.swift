//
// Avianca iOS App.
// Copyright (C) 2020-2021 Avianca S.A. All rights reserved.
// Developed for Avianca by MediaMonks B.V.
//

import MMMCommonCore
import MMMLog

#if SWIFT_PACKAGE
import MMMPromisingResult
#endif

/// Straightforward file-based SnapshotStorage implementation where each snapshot is stored in its own file.
public class FileBasedSnapshotStorage: SnapshotStorage {

	/// Convenience initializer using a directory with the given name under `<sandbox>/Library`.
	public convenience init(libraryDirectory: String) {
		let libraryDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!
		let libraryDirURL = URL(fileURLWithPath: libraryDir, isDirectory: true)
		self.init(rootDirectory: libraryDirURL.appendingPathComponent(libraryDirectory, isDirectory: true))
	}

	public init(rootDirectory: URL) {
		self.rootDirectory = rootDirectory
		MMMLogTrace(self, "Using '\(MMMPathRelativeToAppBundle(rootDirectory.path))'")
	}

	deinit {
		// Let's wait for all the saves to complete.
		// It should be safe to do as our queue is standalone.
		// Note that this is useful only for unit tests because the actual storage in the app is supposed
		// to live indefinitely.
		saveGroup.wait()
	}

	private struct ContainerInfo {
		weak var container: Container?
	}

	// To track all the containers in use. This will be handy when we want to implement lazy saving:
	// can tell each container that is still alive to save their scheduled changes when the app goes
	// to background let say.
	private var containers: [String: ContainerInfo] = [:]

	public func containerForKey(_ key: String) -> SingleSnapshotContainer {

		// TODO: prune `containers` only once in a while, not every time
		containers = containers.filter { $0.value.container != nil }

		if let info = containers[key], let container = info.container {
			return container
		} else {
			let container = Container(parent: self, key: key)
			containers[key] = ContainerInfo(container: container)
			return container
		}
	}

	// MARK: - Things informally available for child objects

	fileprivate let rootDirectory: URL

	// A private serial queue for all our async saves and loads.
	fileprivate lazy var queue = DispatchQueue(
		label: MMMTypeName(Self.self),
		qos: .utility,
		attributes: [],
		autoreleaseFrequency: .workItem,
		target: nil
	)

	// All save operations are added into this group, so we can wait on it in deinit.
	// This is useful only for unit tests as this object is expected to be alive all the time.
	fileprivate let saveGroup = DispatchGroup()

	// MARK: -

	private class Container: SingleSnapshotContainer {

		private weak var parent: FileBasedSnapshotStorage?
		private let key: String
		private let pathURL: URL

		private static var pathCharacters = CharacterSet.urlPathAllowed
			.subtracting(.init(charactersIn: "/"))

		public init(parent: FileBasedSnapshotStorage, key: String) {

			self.parent = parent
			self.key = key

			// Not sure how escaping can fail here.
			let name = key.addingPercentEncoding(withAllowedCharacters: Self.pathCharacters)!
			self.pathURL = parent.rootDirectory
				.appendingPathComponent(name)
				.appendingPathExtension("json") // Not needed, but nicer when debugging.
		}

		public func loadSync<T: Decodable>(_ type: T.Type) throws -> T? {

			guard let parent = parent else { preconditionFailure() }

			// Syncing to the queue makes it easier to test (earlier saves will complete before
			// the test tries to load something).
			// It should be also safe to do as our queue is standalone and is not directly waiting others.
			var snapshot: T?
			try parent.queue.sync {
				snapshot = try _load(type)
			}

			return snapshot
		}

		public func load<T: Decodable>(_ type: T.Type) -> Promising<T?> {

			MMMLogTrace(self, "Loading from '\(key)'...")

			guard let parent = parent else { preconditionFailure() }

			let sink = PromisingResultSink<T?, Error>.init(queue: parent.queue)
			parent.queue.async { [weak self] in
				do {
					sink.push(.success(try self?._load(type)))
				} catch {
					sink.push(.failure(error))
				}
			}

			return sink.drain
		}

		public func save<T: Encodable>(_ snapshot: T) {

			MMMLogTrace(self, "Going to save '\(key)'...")

			guard let parent = parent else { preconditionFailure() }

			// For now it's not lazy, only async.
			parent.queue.async(group: parent.saveGroup) { [self, rootDirectory = parent.rootDirectory, pathURL] in

				// Note that we are capturing `self` strongly here as we need to be able to complete
				// saving in case the container is dropped earlier.

				do {
					try FileManager.default.createDirectory(
						at: rootDirectory,
						withIntermediateDirectories: true,
						attributes: nil
					)
				} catch {
					MMMLogError(self, "Could not create the root directory: \(error.mmm_description)")
				}

				do {
					let data = try JSONEncoder().encode(snapshot)
					try data.write(to: pathURL, options: .atomic)
					MMMLogTrace(self, "Saved as '\(MMMPathRelativeToAppBundle(pathURL.path))'")
				} catch {
					MMMLogError(self, "Could not save to the container keyed by '\(self.key)': \(error.mmm_description)")
				}
			}
		}

		private func _load<T: Decodable>(_ type: T.Type) throws -> T? {

			guard FileManager.default.fileExists(atPath: pathURL.path) else {
				MMMLogTrace(self, "No file at '\(MMMPathRelativeToAppBundle(pathURL.path))', i.e. no previous snapshot")
				return nil
			}

			MMMLogTrace(self, "Reading '\(MMMPathRelativeToAppBundle(pathURL.path))'...")
			return try JSONDecoder().decode(type, from: Data(contentsOf: pathURL))
		}
	}
}
