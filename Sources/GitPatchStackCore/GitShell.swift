import Foundation

public struct CommitSummary {
    public let sha: String
    public let summary: String
}

extension CommitSummary: CustomStringConvertible {
    public var description: String {
        return "\(self.sha.prefix(6)) \(self.summary)"
    }
}

public class GitShell {
    public enum Error: Swift.Error {
        case gitLogFailure
        case gitFetchFailure
        case gitRebaseFailure
        case gitUncommittedChangePresentFailure
        case gitCheckedOutBranchFailure
        case gitCreateAndCheckoutFailure
        case gitCherryPickCommitsFailure
        case gitShaOfFailure
        case gitCommitMessageOfFailure
        case gitCommitAmendMessages
        case gitRevListFailure
        case gitForceBranchFailure
        case gitDeleteBranchFailure
        case gitCheckoutFailure
        case gitCommitSummaryFailure
        case gitCreateBranchFailure
        case gitCherryPickFailure
        case gitCherryPickAbortFailure
        case gitForcePushFailure
        case gitPushFailure
        case gitDeleteRemoteBranchFailure
        case gitMergeBaseFailure
    }

    private let path: String

    public init(bash: Bash, path: String? = nil) throws {
        if let p = path {
            self.path = p
        } else {
            self.path = try bash.which("git")
        }
    }

    public func commits(from fromRef: String, to toRef: String) throws -> [CommitSummary] {
        let result = try run(self.path, arguments: ["log", "--pretty=%H %s", "\(fromRef)..\(toRef)"])
        guard result.isSuccessful else { throw Error.gitLogFailure }

        if let output = result.standardOutput {
            let lines = output.split { $0.isNewline }

            return lines.map { (line) -> CommitSummary in
                let firstSpace = line.firstIndex(of: " ")!
                let sha = String(line.prefix(upTo: firstSpace))
                let summary = line.suffix(from: firstSpace).trimmingCharacters(in: .whitespacesAndNewlines)
                return CommitSummary(sha: sha, summary: summary)
            }
        }
        return []
    }

    public func fetch(remote: String, branch: String) throws {
        let result = try run(self.path, arguments: ["fetch", "--quiet", remote, branch])
        guard result.isSuccessful else {
            throw Error.gitFetchFailure
        }
    }

    public func show(commit: String) {
        replaceProcess(self.path, command: "git", arguments: ["show", "--pretty=raw", commit])
    }

    public func rebase(onto: String, from: String, to: String, interactive: Bool = false) throws {
        if interactive {
            // Note: We don't need to handle explicit error output here because
            // this replaces the process and therefore all standard out and error
            // output will naturally endup in the shell.
            replaceProcess(self.path, command: "git", arguments: ["rebase", "-i", "--onto", onto, from, to])
        } else {
            let result = try run(self.path, arguments: ["rebase", "--onto", onto, from, to])
            guard result.isSuccessful else {
                if let output = result.standardOutput, !output.isEmpty {
                    print(output)
                }
                if let errOutput = result.standardError, !errOutput.isEmpty {
                    print(errOutput)
                }
                throw Error.gitRebaseFailure
            }
        }
    }

    public func uncommittedChangePresent() throws -> Bool {
        let result = try run(self.path, arguments: ["status", "--porcelain"])
        guard result.isSuccessful else {
            throw Error.gitUncommittedChangePresentFailure
        }

        guard let output = result.standardOutput else {
            throw Error.gitUncommittedChangePresentFailure
        }

        if output == "" {
            return false
        } else {
            return true
        }
    }

    public func getCheckedOutBranch() throws -> String {
        let result = try run(self.path, arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
        guard result.isSuccessful else {
            throw Error.gitCheckedOutBranchFailure
        }

        guard let output = result.standardOutput else {
            throw Error.gitCheckedOutBranchFailure
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func createAndCheckout(branch: String, startingFrom: String, tracking: Bool = false) throws {
        var result: RunResult?
        if tracking == true {
            result = try run(self.path, arguments: ["checkout", "-B", branch, "--track", startingFrom])
        } else {
            result = try run(self.path, arguments: ["checkout", "-B", branch, "--no-track", startingFrom])
        }

        guard let res = result, res.isSuccessful == true else {
            throw Error.gitCreateAndCheckoutFailure
        }
    }

    public func cherryPickCommits(from: String, to: String) throws {
        print("- cherry picking \(from)..\(to)")

        if try self.revList(from: from, to: to).isEmpty {
            return
        }

        let result = try run(self.path, arguments: ["cherry-pick", "\(from)..\(to)"])
        guard result.isSuccessful == true else {
            if let output = result.standardOutput {
                print(output)
            }
            if let errOutput = result.standardError {
                print(errOutput)
            }
            throw Error.gitCherryPickCommitsFailure
        }
    }

    public func cherryPick(ref: String) throws {
        let result = try run(self.path, arguments: ["cherry-pick", "\(ref)"])
        guard result.isSuccessful == true else {
            if let errOutput = result.standardOutput {
                print(errOutput)
            }
            throw Error.gitCherryPickFailure
        }
    }

    public func cherryPickAbort() throws {
        let result = try run(self.path, arguments: ["cherry-pick", "--abort"])
        guard result.isSuccessful == true else {
            if let errOutput = result.standardOutput {
                print(errOutput)
            }
            throw Error.gitCherryPickAbortFailure
        }
    }

    public func getShaOf(ref: String) throws -> String {
        let result = try run(self.path, arguments: ["rev-list", "-n1", ref])
        guard result.isSuccessful == true else {
            throw Error.gitShaOfFailure
        }

        guard let output = result.standardOutput else {
            throw Error.gitShaOfFailure
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func commitMessageOf(ref: String) throws -> String {
        let result = try run(self.path, arguments: ["rev-list", "--format=%B", "--max-count=1", ref])
        guard result.isSuccessful == true else {
            throw Error.gitCommitMessageOfFailure
        }

        guard let output = result.standardOutput else {
            throw Error.gitCommitMessageOfFailure
        }

        if let firstNewlineIndex = output.firstIndex(of: "\n") {
            var out = output
            out.removeSubrange(...firstNewlineIndex)
            return out
        } else {
            throw Error.gitCommitMessageOfFailure
        }
    }

    public func commitAmendMessages(messages: [String]) throws {
        var args = ["commit", "--amend"]
        for msg in messages {
            args.append("-m")
            args.append(msg)
        }
        let result = try run(self.path, arguments: args)
        guard result.isSuccessful == true else {
            throw Error.gitCommitMessageOfFailure
        }
    }

    public func revList(from: String, to: String) throws -> [String] {
        let result = try run(self.path, arguments: ["rev-list", "\(from)..\(to)"])
        guard result.isSuccessful == true else {
            throw Error.gitRevListFailure
        }

        guard let output = result.standardOutput else {
            throw Error.gitRevListFailure
        }

        return output.split(separator: "\n").map { String($0) }
    }

    public func forceBranch(named: String, to: String) throws {
        let result = try run(self.path, arguments: ["branch", "-f", named, to])
        guard result.isSuccessful == true else {
            throw Error.gitForceBranchFailure
        }
    }

    public func deleteBranch(named: String) throws {
        let result = try run(self.path, arguments: ["branch", "-D", named])
        guard result.isSuccessful == true else {
            throw Error.gitDeleteBranchFailure
        }
    }

    public func deleteRemoteBranch(named branch: String, remote: String) throws {
        let result = try run(self.path, arguments: ["push", remote, ":\(branch)"])
        guard result.isSuccessful == true else {
            throw Error.gitDeleteRemoteBranchFailure
        }
    }

    public func checkout(ref: String) throws {
        let result = try run(self.path, arguments: ["checkout", ref])
        guard result.isSuccessful == true else {
            throw Error.gitCheckoutFailure
        }
    }

    public func commitSummary(_ ref: String) throws -> CommitSummary {
        guard let commit = try self.commits(from: "\(ref)^", to: ref).first else {
            throw Error.gitCommitSummaryFailure
        }
        return commit
    }

    public func createBranch(named: String, on: String) throws {
        let result = try run(self.path, arguments: ["branch", "-f", "-q", "--no-track", named, on])
        guard result.isSuccessful == true else {
            throw Error.gitCreateBranchFailure
        }
    }

    public func findDotGit() throws -> URL? {
        let result = try run(self.path, arguments: ["rev-parse", "--show-toplevel"])
        guard result.isSuccessful == true else {
            return nil
        }

        guard let output = result.standardOutput else {
            return nil
        }

        let repositoryTopLevelPath = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathComponents = [repositoryTopLevelPath, ".git"]

        guard let dotGitURL = NSURL.fileURL(withPathComponents: pathComponents) else {
            return nil
        }

        if directoryExists(atPath: dotGitURL.path) {
            return dotGitURL
        } else {
            return nil
        }
    }

    public func forcePush(branch: String, upToRemote remote: String, displayOutput: Bool = false) throws {
        let result = try run(self.path, arguments: ["push", "-f", "-q", remote, "\(branch):\(branch)"])
        guard result.isSuccessful == true else {
            throw Error.gitForcePushFailure
        }

        if displayOutput {
            if let output = result.standardOutput {
                let cleansedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleansedOutput != "" {
                    print(cleansedOutput)
                }
            }
            if let errOutput = result.standardError {
                let cleansedErrOutput = errOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleansedErrOutput != "" {
                    print(cleansedErrOutput)
                }
            }
        }
    }

    public func push(localBranch: String, upToRemote remote: String, remoteBranch: String) throws {
        let result = try run(self.path, arguments: ["push", remote, "\(localBranch):\(remoteBranch)"])
        guard result.isSuccessful == true else {
            throw Error.gitPushFailure
        }
    }

    public func mergeBase(refA: String, refB: String) throws -> String {
        let result = try run(self.path, arguments: ["merge-base", refA, refB])
        guard result.isSuccessful == true else {
            throw Error.gitMergeBaseFailure
        }

        guard let output = result.standardOutput else {
            throw Error.gitMergeBaseFailure
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

fileprivate func directoryExists(atPath path: String) -> Bool {
    var isDirectory = ObjCBool(true)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}
