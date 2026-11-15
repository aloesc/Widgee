import Foundation

/// Минимальный SemVer: MAJOR.MINOR.PATCH с необязательными -prerelease / +build.
public struct SemVer: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    public init?(_ string: String) {
        let core = string.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }),
                  p == "0" || !p.hasPrefix("0"), let n = Int(p) else { return nil }
            nums.append(n)
        }
        self.init(major: nums[0], minor: nums[1], patch: nums[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (l: SemVer, r: SemVer) -> Bool {
        (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
    }
}
