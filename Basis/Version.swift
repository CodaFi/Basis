//
//  Version.swift
//  Basis
//
//  Created by Robert Widmann on 10/10/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//  Released under the MIT license.
//

/// Represents the version of a piece of software.
///
/// Versions are equal if they have the same number, value, and ordering of branch versions and the 
/// same tags that may not necessarily be in the same order.  
public struct Version {
	public let versionBranch : [Int]
	public let versionTags : [String]

	public init(_ versionBranch : [Int], _ versionTags : [String]) {
		self.versionBranch = versionBranch
		self.versionTags = versionTags
	}
}

extension Version : Equatable {}

public func ==(lhs : Version, rhs : Version) -> Bool {
	return lhs.versionBranch == rhs.versionBranch && sort(lhs.versionTags) == sort(rhs.versionTags)
}

extension Version : CustomStringConvertible {
	public var description : String {
		get {
      let versions : [Character] = concat(intersperse(["."])(self.versionBranch.compactMap({ (b : Int) in b.description.map{$0} })))
      let tags = concatMap({ (xs : [Character]) -> [Character] in ["-"] + xs })(self.versionTags.map{$0.map{$0}})
			return String(versions + tags)
		}
	}
}
