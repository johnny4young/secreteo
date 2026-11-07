import DictationAgents
import Foundation

await DictationMCPCommand.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    executable: URL(fileURLWithPath: CommandLine.arguments[0]))
