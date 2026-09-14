import Foundation

/// Owns the existing icon-preview catalog in a module without generated string symbols.
public enum WhereAssetBundle {
    public static var bundle: Bundle {
        .module
    }
}
