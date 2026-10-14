import CoreGraphics
import Foundation

let opts = CGWindowListOption([.optionOnScreenOnly])
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for w in list {
    let owner = w[kCGWindowOwnerNameKey as String] as? String ?? ""
    let name = w[kCGWindowNameKey as String] as? String ?? ""
    if owner.lowercased().contains("fifastreet") || name.lowercased().contains("fifastreet") {
        if let num = w[kCGWindowNumberKey as String] as? Int {
            print(num)
            exit(0)
        }
    }
}
exit(1)
