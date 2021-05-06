//
// MMMPromisingResult. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import Foundation

/// A promise-like type using `Swift.Result` as its value. This part is to be seen by the user code,
/// the one that is interested in consumption or transformation of the result, not providing it.
/// You cannot initialize it directly, see `PromisingResultSink` for the part where the value can be pushed to.
///
/// - Note: You must keep a reference to this object or the corresponding callback chain will be cancelled.
///
/// I would like to try this for one-time sequential operations as a lighter version of `MMMLoadable`
/// or usual promises. (And we cannot use Combine just yet.) If you want to use other similar libs,
/// then it should be easy to make an adapter. No extra features expected. It's reinventing the bicycle,
/// but is not always a bad idea.
///
/// (The name is a bad pun on the "results" inner joke and this thing being related to promises.)
public class PromisingResult<Success, Error: Swift.Error> {

	fileprivate typealias Sink = PromisingResultSink<Success, Error>

	private let sink: Sink

	fileprivate init(_ sink: Sink) {
		self.sink = sink
	}

	/// An instance that is a failure from the start.
	public static func failure(_ error: Error) -> PromisingResult<Success, Error> {
		let sink = Sink()
		sink.push(.failure(error))
		return sink.drain
	}

	/// An instance that is a success from the start.
	public static func success(_ success: Success) -> PromisingResult<Success, Error> {
		let sink = Sink()
		sink.push(.success(success))
		return sink.drain
	}

	/// Sets a closure to call when the result is ready.
	///
	/// Only a single transform or completion can be set.
	/// Can be set after the result is available, still will be called.
	public func completion(_ completion: @escaping (Result<Success, Error>) -> Void) -> Self {
		sink.completion(completion)
		return self
	}

	/// Sets a closure to call on the given queue when the result is ready.
	///
	/// Only a single transform or completion can be set.
	/// Can be set after the result is available, still will be called.
	public func completion(queue: DispatchQueue, _ completion: @escaping (Result<Success, Error>) -> Void) -> Self {
		sink.completion { result in
			queue.async { completion(result) }
		}
		return self
	}

	/// When the result is ready and is successful, then it's passed to the given closure;
	/// when it's ready but is a failure, then it's directly passed further.
	/// (This is like `transformSuccess()`, but when the result of the transformation is async.)
	public func then<NewSuccess>(
		queue: DispatchQueue? = nil,
		_ callback: @escaping (Success) -> PromisingResult<NewSuccess, Error>
	) -> PromisingResult<NewSuccess, Error> {
		let queue = queue ?? sink.queue
		let r = PromisingResultSink<NewSuccess, Error>(queue: queue, dependency: sink)
		sink.completion { result in
			queue.async {
				switch result {
				case .failure(let error):
					r.push(.failure(error))
				case .success(let success):
					r.sourceFrom(callback(success))
				}
			}
		}
		return r.drain
	}

	/// Sets a transformation to perform on the result when it's ready.
	///
	/// Only a single transform or completion can be set.
	/// Can be set after the result is available, still will be called.
	///
	/// Note that I did not want to use `flatMap` already used with `Swift.Result` as its use is confusing there.
	/// One can use mapping functions of the result in the closure.
	public func transform<NewSuccess, NewError>(
		_ transform: @escaping (Result<Success, Error>) -> Result<NewSuccess, NewError>
	) -> PromisingResult<NewSuccess, NewError> {
		let r = PromisingResultSink<NewSuccess, NewError>(queue: sink.queue, dependency: sink)
		sink.completion {
			r.push(transform($0))
		}
		return r.drain
	}

	/// Sets a transformation to perform on the result when it's ready and is a success.
	/// (A failure is going to be passed as is.)
	/// This is an alternative to `transform` when there is no need in transforming the failure.
	public func transformSuccess<NewSuccess>(
		_ transform: @escaping (Success) -> Result<NewSuccess, Error>
	) -> PromisingResult<NewSuccess, Error> {
		return self.transform {
			switch $0 {
			case .failure(let e):
				return Result<NewSuccess, Error>.failure(e)
			case .success(let value):
				return transform(value)
			}
		}
	}

	/// Sets a transformation to perform on the result when it's ready and is a failure.
	/// (A success is going to be passed as is.)
	/// This is an alternative to `transform` when there is no need in transforming the success.
	/// Note that it's not called `transformFailure` because it gets an associated value of `.failure`.
	public func transformError<NewError>(
		_ transform: @escaping (Error) -> NewError
	) -> PromisingResult<Success, NewError> {
		return self.transform {
			switch $0 {
			case .failure(let e):
				return .failure(transform(e))
			case .success(let value):
				return .success(value)
			}
		}
	}
}

/// An alias for `PromisingResult` where `Error` type is a generic Swift `Error`.
/// This is because we rarely restrict possible errors in our interfaces.
public typealias Promising<Success> = PromisingResult<Success, Swift.Error>

/// A promise-like type using `Swift.Result` as its value. This part is for code owning the initial result,
/// i.e. the part that can fulfill it. Return `PromisingResult` (see `drain`) to the user code interested
/// only in consumption of the result.
public class PromisingResultSink<Success, Error: Swift.Error> {

	fileprivate let queue: DispatchQueue

	private var dependency: AnyObject?

	/// - Parameter queue: A serial queue to sync against. `DispatchQueue.main` by default.
	///
	/// - Parameter dependency: An optional opaque reference for this sink to keep alive. This might be an object
	///   that is going to push the result eventually and wishing its lifetime to be connected to that of the sink.
	public init(queue: DispatchQueue? = nil, dependency: AnyObject? = nil) {
		self.queue = queue ?? DispatchQueue.main
		self.dependency = dependency
	}

	public typealias ResultType = Result<Success, Error>

	/// The result promised, if available.
	///
	/// Initially was supposed to be private and cleaned as soon as passed to the completion,
	/// however it might be interesting to keep it for diagnostics or for deferred consumption.
	public private(set) var result: ResultType?

	/// A closure to pass the result to. It's enough to support just one.
	private var completion: ((ResultType) -> Void)?

	/// `true` when the completion callback has been called and then dropped.
	private var isCompleted = false

	/// Called once by the owner to pass the result down the completion callback chain.
	/// If no next callback is set yet, then the result will be stored temporarily till the callback is set.
	///
	/// (I started with the usual `fulfill()` name, but it has meaning of successfully finishing it.
	/// Before that I thought about `complete()` but it was too close to `completion()`.)
	public func push(_ result: ResultType) {
		queue.async { [weak self] in
			// It could be that the request is cancelled/dropped earlier than it is completed.
			guard let self = self else { return }
			guard self.result == nil else {
				assertionFailure("Trying to complete \(type(of: self)) more than once")
				return
			}
			self.result = result
			self.completeIfPossible()
		}
	}

	private var parent: PromisingResult<Success, Error>?

	/// Allows to use the result of another callback chain as the result of this one.
	/// Only one such a parent chain can be attached.
	public func sourceFrom(_ parent: PromisingResult<Success, Error>) {
		queue.async { [weak self] in
			// It could be that the request is cancelled/dropped earlier than it is completed.
			guard let self = self else { return }
			guard self.parent == nil else {
				assertionFailure("Trying to attach \(type(of: self)) more than once")
				return
			}
			self.parent = parent
			_ = parent.completion { [weak self] in
				self?.push($0)
			}
		}
	}

	private func completeIfPossible() {

		guard let completion = self.completion, let result = result else {
			// Something not ready yet, fine, will check later.
			return
		}

		guard !isCompleted else {
			assertionFailure("\(type(of: self)) has been already completed")
			return
		}
		isCompleted = true

		// Let's discard the completion asap to cut any references.
		self.completion = nil
		// Don't need to discard the result however, might be useful to examine it.

		completion(result)
	}

	/// Sets the next callback in the chain. To be called by `PromisingResult` only.
	fileprivate func completion(_ completion: @escaping (ResultType) -> Void) {
		queue.async { [weak self] in
			// Again, it could be that the request is cancelled/dropped earlier than a completion is set.
			guard let self = self else { return }
			guard self.completion == nil, !self.isCompleted else {
				assertionFailure("Trying to set a completion callback on \(type(of: self)) more than once")
				return
			}
			self.completion = completion
			self.completeIfPossible()
		}
	}

	/// Returns the part of this object suitable for external users, the ones who are not supposed to fulfill it.
	public private(set) lazy var drain = PromisingResult<Success, Error>(self)
}
