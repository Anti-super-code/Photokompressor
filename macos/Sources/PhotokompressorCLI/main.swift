import PhotokompressorCore
import Foundation

VipsRuntime.ensureInitialized()
let args = Array(CommandLine.arguments.dropFirst())

// Dev-only: exercises FinderIntegration's real Quick Action install/remove
// without needing the full GUI app bundle. Not part of the documented CLI.
if args.first == "--dev-register-quickaction", args.count > 1 {
    try FinderIntegration.register(appPathOverride: args[1])
    print("registered: \(FinderIntegration.isRegistered())")
    exit(0)
}
if args.first == "--dev-unregister-quickaction" {
    try FinderIntegration.unregister()
    print("registered: \(FinderIntegration.isRegistered())")
    exit(0)
}

exit(CliRunner.run(args))
