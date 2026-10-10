import Foundation
import MochiAI

@main
enum MochiBenchmarkCommand {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("Usage: mochi-benchmark <dataset.json> [report.json] [decisions.json]\n".utf8))
            return
        }
        let inputURL = URL(fileURLWithPath: arguments[1])
        let outputURL = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2]) : nil
        let cases = try JSONDecoder.mochi.decode([BenchmarkCase].self, from: Data(contentsOf: inputURL))
        let decisions: [String: String]
        if arguments.count >= 4 {
            decisions = try JSONDecoder.mochi.decode(
                [String: String].self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[3]))
            )
        } else {
            decisions = [:]
        }
        let provider = StaticDecisionProvider(decisions: decisions)
        let report = await BenchmarkRunner().run(cases: cases, provider: provider)
        let data = try JSONEncoder.mochi.encode(report)
        if let outputURL { try data.write(to: outputURL, options: .atomic) }
        else { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)) }
    }
}
