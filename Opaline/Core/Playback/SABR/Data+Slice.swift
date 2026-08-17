import Foundation

extension Data {
    /// `count`-relative slice.
    ///
    /// `Data` does not have to be indexed from zero — dropping bytes off the
    /// front moves `startIndex` — so subranges must be built off `startIndex`
    /// rather than off 0. Getting this wrong traps at runtime.
    func slice(from offset: Int, length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= count else {
            return nil
        }
        let base = startIndex + offset
        // A slice shares storage instead of copying — a 3MB segment copied per
        // request is both a memory spike and a chunk of the CPU.
        return self[base..<(base + length)]
    }
}
