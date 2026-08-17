import PhotokompressorCore
import Foundation

VipsRuntime.ensureInitialized()
let args = Array(CommandLine.arguments.dropFirst())
exit(CliRunner.run(args))
