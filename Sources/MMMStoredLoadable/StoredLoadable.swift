//
// MMMSnapshotStorage. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import MMMCommonCore
import MMMLoadable
import MMMLog
import MMMPromisingResult

#if SWIFT_PACKAGE
import MMMSnapshotStorage
#endif

/// A loadable that stores the `Content` entity, and checks against the `InvalidationPolicy`.
///
/// This can be used like a regular `MMMLoadable`, however, it checks if we have content stored before calling `doSync`.
///
/// Please make sure to override `setDidSyncSuccessfully(content:)`, and call
/// `super.setDidSyncSuccessfully(content:)` there. Call this method instead of
/// `setDidSyncSuccessfully` when you're done syncing, .
open class StoredLoadable<Content: Codable>: MMMLoadable {
	
	/// Something that wraps the `Content` with the date when we stored it; so we can compare this to the
	/// `InvalidationPolicy`.
	private struct Wrapper: Codable {
		
		public let content: Content
		public let date: Date
		
		public init(content: Content, date: Date = Date()) {
			self.content = content
			self.date = date
		}
	}
	
	private let storage: SingleSnapshotContainer?
	private let policy: InvalidationPolicy
	private let populateDirectly: Bool
	private let queue: DispatchQueue?
	
	/// Initialize a new `StoredLoadable`, the `storage` container should be provided by the owner of this class.
	/// - Parameters:
	///   - storage: The container to store the loadable content in.
	///   - policy: The policy to use for invalidating the storage.
	///	  - populateDirectly: If we should first populate the loadable
	///	  					  (e.g. call `setDidSyncSuccessfully(content:)`) even when the cache is
	///	  					  invalid, and then actually sync.
	///	  - queue: What queue we should execute from when loading from SnapshotStorage, defaults to `main`, you
	///	  		   can pass `nil` to not switch queues.
	public init(
		storage: SingleSnapshotContainer?,
		policy: InvalidationPolicy? = nil,
		populateDirectly: Bool = false,
		queue: DispatchQueue? = .main
	) {
		
		self.storage = storage
		self.policy = policy ?? .never
		self.populateDirectly = populateDirectly
		self.queue = queue
		
		super.init()
	}
	
	/// Overriding the `sync` method in `MMMLoadable`, using the same base implementation, except for checking
	/// cache when `!isContentsAvailable`. This allows the `StoredLoadable` to behave much like a regular
	/// loadable, except for the fact that a user should implement `didSyncSuccessfully(content:isStored:)`.
	public final override func sync() {
		
		guard loadableState != .syncing else {
			// Syncing is in progress already, ignoring the new request.
			return
		}
		
		// Now we check if we can load from storage, as long as content is not available.
		if !isContentsAvailable {
			// No contents available, let's try to grab them from storage first.
			loadableState = .syncing
			loadFromStorage()
		} else {
			// Content is available, we call super to continue with the regular flow.
			super.sync()
		}
	}
	
	@available(*, renamed: "setDidSyncSuccessfully(content:)", unavailable)
	open override func setDidSyncSuccessfully() {
		assertionFailure("Use setDidSyncSuccessfully(content:) instead")
	}
	
	open func setDidSyncSuccessfully(content: Content) {
		super.setDidSyncSuccessfully()
		
		storeInStorage(content: content)
	}
	
	/// The asynchronous request when trying to load from storage.
	private var storageRequest: Promising<Wrapper?>?
	
	/// Checks the storage (asynchronous) for a valid instance.
	private func loadFromStorage() {
		
		guard let storage = storage else {
			// Alright, we're done here.
			doSync()
			return
		}
		
		storageRequest = storage.load(Wrapper.self).completion { [weak self] result in
			
			guard let self = self else { return }
			
			func execute() {
				
				let typeName = MMMTypeName(Content.self)
				
				switch result {
				case .failure:
				
					MMMLogError(self, "Error loading \(typeName) from storage, syncing...")
					
					self.doSync()
					
				case .success(nil):
					
					MMMLogTrace(self, "No storage for \(typeName) yet, syncing...")
					
					self.doSync()
					
				case .success(.some(let wrapper)):
					
					if wrapper.date.isValid(using: self.policy) {
						MMMLogTrace(self, "Found valid storage for \(typeName)")
						
						self.didLoadFromStorage(wrapper: wrapper)
						
					} else if self.populateDirectly {
						MMMLogTrace(self, "Storage invalid for \(typeName), but populating directly and syncing again")
						
						self.didLoadFromStorage(wrapper: wrapper)
						self.doSync()
						
					} else {
						MMMLogTrace(self, """
						Storage expired for \(typeName), \
						failed by policy \(self.policy) \
						created at \(wrapper.date), syncing...
						""")
						
						self.doSync()
					}
				}
			}
			
			if let queue = self.queue {
				queue.async {
					execute()
				}
			} else {
				execute()
			}
		}
	}
	
	/// We store the date of a `Wrapper` loaded from storage, so we can check if the content is still valid in `needsSync()`.
	private var storedDate: Date?
	private var avoidStorage = false
	
	/// Gets called when we successfully load from storage.
	private func didLoadFromStorage(wrapper: Wrapper, directlyPopulated: Bool = false) {
		
		avoidStorage = true
		
		if !directlyPopulated {
			// Don't upate the storedDate when we populated directly, since this will
			// influence 'needsSync'.
			storedDate = wrapper.date
		}
		
		setDidSyncSuccessfully(content: wrapper.content)
		avoidStorage = false
	}
	
	/// Call this to store the `Content` to the storage, e.g. when syncing successfully. Make sure to *not* call this
	/// when coming from `didSyncSuccessfully(content:isStored:)` and `isStored` is `true`.
	private func storeInStorage(content: Content) {
		
		guard let storage = storage, !avoidStorage else {
			// Alright, we're done here.
			return
		}
		
		let wrapper = Wrapper(content: content)
		
		storedDate = wrapper.date
		
		storage.save(wrapper)
	}
	
	/// If this loadable needs syncing (e.g. when calling `syncIfNeeded()`), this method now also checks if the cache
	/// is invalid.
	public override func needsSync() -> Bool {
	
		if super.needsSync() {
			return true
		}
		
		guard let date = storedDate else {
			return false
		}
		
		// If storage is invalid, we'll need a sync.
		return !date.isValid(using: policy)
	}
}

extension Date {
	
	fileprivate func isValid(using policy: InvalidationPolicy) -> Bool {
		
		// Since the date is in the past, we invert it.
		let age = -timeIntervalSinceNow
		
		guard let interval = policy.duration else {
			// No interval, always valid storage.
			return true
		}
		
		// The interval we refresh in is still larger than the age, so this is
		// valid storage.
		return interval > age
	}
}
