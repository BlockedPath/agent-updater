// Prints the window number of Agent Updater's main window (largest on-screen window it owns).
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: (Int, Double) = (0, 0)
for w in list where (w[kCGWindowOwnerName as String] as? String ?? "").contains("Agent Updater") {
  let b = w[kCGWindowBounds as String] as! [String: Double]
  let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
  if area > best.1 { best = (w[kCGWindowNumber as String] as! Int, area) }
}
print(best.0)
