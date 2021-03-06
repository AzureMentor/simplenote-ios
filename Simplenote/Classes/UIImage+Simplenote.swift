import Foundation
import UIKit


// MARK: - Simplenote's UIImage Static Methods
//
extension UIImage {

    /// Returns the Pinned Icon, to be used by the Notes List
    ///
    @objc
    static var pinImage: UIImage {
        return UIImage(named: "icon_pin")!
    }

    /// Returns the Shared Icon, to be used by the Notes List
    ///
    @objc
    static var sharedImage: UIImage {
        return UIImage(named: "icon_shared")!
    }
}
