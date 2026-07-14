import CapsomniaPmsetHelperCore
import Darwin
import Foundation

private let usage = "usage: com.github.oonishidaichi.capsomnia.pmset-helper on|off|display-sleep\n"

guard let command = HelperCommand(arguments: Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(EX_USAGE)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
process.arguments = command.pmsetArguments
process.standardInput = FileHandle.nullDevice

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    let message = "pmset-helper: could not run /usr/bin/pmset: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EX_SOFTWARE)
}

