//
// MMMSnapshotStorage. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import Foundation

public enum InvalidationPolicy {
	/// Never invalidate the storage.
	case never
	/// Invalidate the storage every hour.
	case hourly
	/// Invalidate the storage every day.
	case daily
	/// Custom invalidation, number of seconds.
	case custom(TimeInterval)
	
	/// How long we mark the storage as 'valid', in seconds.
	internal var duration: TimeInterval? {
		switch self {
		case .never: return nil
		case .hourly: return 60 * 60
		case .daily: return 60 * 60 * 24
		case .custom(let interval): return interval
		}
	}
}
