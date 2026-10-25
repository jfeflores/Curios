import Foundation
import CuriosCore

// Only used by the isolated legacy UI regressions, never compiled into Curios.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
guard folder.lastPathComponent.hasPrefix("ui-test-") else { fatalError("Expected a synthetic UI test profile") }
let url = Persistence.defaultURL(environment: ["CURIOS_DATA_DIR": folder.path])
try Persistence(url: url).save(.sample())
