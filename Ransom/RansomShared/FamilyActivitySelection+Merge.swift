import FamilyControls

public extension FamilyActivitySelection {
    /// This selection plus everything in `other`, never less.
    ///
    /// `FamilyActivitySelection` is three separate token sets and nothing in the
    /// framework combines them, so a union written by hand at each call site is
    /// three chances to forget one - and forgetting the web domains means a
    /// commitment that quietly stops covering Safari.
    func merging(_ other: FamilyActivitySelection) -> FamilyActivitySelection {
        var merged = self
        merged.applicationTokens.formUnion(other.applicationTokens)
        merged.categoryTokens.formUnion(other.categoryTokens)
        merged.webDomainTokens.formUnion(other.webDomainTokens)
        return merged
    }
}
