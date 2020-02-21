import Foundation

public final class GitPatchStack {
    public enum Error: Swift.Error {
        case invalidArgumentCount
    }

    private let arguments: [String]
    private let remote: String
    private let baseBranch: String

    private let git: GitShell

    private var remoteBase: String {
        return "\(self.remote)/\(self.baseBranch)"
    }

    public init(arguments: [String] = CommandLine.arguments, remote: String = "origin", baseBranch: String = "master") throws {
        self.arguments = arguments
        self.remote = remote
        self.baseBranch = baseBranch
        self.git = try GitShell(bash: Bash())
    }

    public func run() throws {

        guard self.arguments.count >= 2 else {
            throw Error.invalidArgumentCount
        }

        let subcommand = self.arguments[1]
        switch subcommand {
        case "ls":
            try self.list()
        case "show":
            guard self.arguments.count == 3 else {
                throw Error.invalidArgumentCount
            }

            if let index = Int(self.arguments[2]) {
                try self.show(patchIndex: index)
            } else {
                print("Usage: git-ps show <patch-index>")
                print("Note: Run 'git-ps ls' to see the current patches an their index values")
            }
        case "pull":
            try self.pull()
        case "rebase":
            try self.rebase()
        case "rr":
            guard self.arguments.count == 3 else {
                throw Error.invalidArgumentCount
            }

            if let index = Int(self.arguments[2]) {
                try self.requestReview(patchIndex: index)
            } else {
                print("Usage: git-ps rr <patch-index>")
                print("Note: Run 'git-ps ls' to see the current patches an their index values")
            }
        case "pub":
            // TODO:
            self.publish()
        default:
            print("default")
        }



//            print(try! Bash().which("git"))
//
//            let outputPipe = Pipe()
//            let errorPipe = Pipe()
//            let task = Process()
//            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
//            task.arguments = ["--version"]
//            task.standardOutput = outputPipe
//            task.standardError = errorPipe
//
//            // run command
//
//            try! task.run()
//
//            // once complete
//
//            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
//            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
//
//            let output = String(data: outputData, encoding: .utf8)
//            let error = String(data: errorData, encoding: .utf8)

//            let result = run("/usr/bin/git", arguments: ["--version"])

//
//            print("DREW: output:")
//            print(output)
//            print("DREW: error:")
//            print(error)
    }

    public func list() throws {
        let patches = try self.patchStack()
        patches.enumerated().reversed().forEach { (offset: Int, commitSummary: CommitSummary) in
            print("\(offset) \(String(describing: commitSummary))")
        }
    }

    public func show(patchIndex: Int) throws {
        guard let patch = try self.getPatch(index: patchIndex) else {
            print("Error: there is no patch with an index of \(patchIndex)")
            return
        }

        self.git.show(commit: patch.sha)
    }

    public func pull() throws {
        try self.git.fetch(remote: self.remote, branch: self.baseBranch)
        try self.git.rebase(onto: self.remoteBase, from: self.remoteBase, to: self.baseBranch)
    }

    public func rebase() throws {
        try self.git.rebase(onto: self.remoteBase, from: self.remoteBase, to: self.baseBranch, interactive: true)
    }

    public func requestReview(patchIndex: Int) throws {
        guard let patch = try self.getPatch(index: patchIndex) else {
            print("Error: there is no patch with an index of \(patchIndex)")
            return
        }

        guard try !self.git.uncommittedChangePresent() else {
            print("Error: uncommited changes are present")
            print("Please commit or stash any uncommitted changes before running this command.")
            return
        }

        let originalBranch = try self.git.getCheckedOutBranch()

        if let uuid = try self.getId(patch: patch) {
            print("DREW: got uuid: \(uuid.uuidString)")
            // already have id on commit, just need to request review
        } else {
            // add id to commit
            print("DREW: would add id to it")
            //        try self.addIdTo(uuid: UUID(), patch: patch)
        }

        // Do this so that we are always creating PR branches on top of the latest remote baseBranch
//        try self.git.fetch(remote: self.remote, branch: self.baseBranch)

        // FUTURE: generate new patch stack request review branch name (maybe use first X characters of summary and some sort of slug algo)

        // create the new request review branch on remote base

        // checkout the new branch

        // cherry pick selected commit sha into branch

            // if fails to cherry pick

            // cherry pick abort

            // checkout original branch

            // exit with error

        // push branch up to remote

        // checkout original branch
    }

    public func publish() {
        print("publish")

        // get the sha of the commit to publish upstream
    }

    private func patchStack() throws -> [CommitSummary] {
        let patches = try git.commits(from: self.remoteBase, to: self.baseBranch)
        return patches.reversed() // reverse so indexing is 0 closest to origin, u
    }

    private func getPatch(index: Int) throws -> CommitSummary? {
        let patches = try self.patchStack()
        guard (index >= 0) && (index < patches.count) else { return nil }
        return patches[index]
    }

    private func addIdTo(uuid: UUID, patch: CommitSummary) throws -> CommitSummary {
        let originalBranch = try self.git.getCheckedOutBranch()
        try self.git.createAndCheckout(branch: "ps/tmp/add_id_rework", startingFrom: self.remoteBase)
        try self.git.cherryPickCommits(from: self.remoteBase, to: patch.sha)
        let shaOfPatchPrime = try self.git.getShaOf(ref: "HEAD")
        let originalMessage = try self.git.commitMessageOf(ref: shaOfPatchPrime)
        try self.git.commitAmendMessages(messages: [originalMessage, "ps-id: \(uuid.uuidString)"])
        let shaOfPatchFinalPrime = try self.git.getShaOf(ref: "HEAD")
        try self.git.cherryPickCommits(from: patch.sha, to: self.baseBranch)
        try self.git.forceBranch(named: self.baseBranch, to: "HEAD")
        try self.git.checkout(ref: originalBranch)
        try self.git.deleteBranch(named: "ps/tmp/add_id_rework")
        return try self.git.commitSummary(shaOfPatchFinalPrime)
    }

    private func getId(patch: CommitSummary) throws -> UUID? {
        let message = try self.git.commitMessageOf(ref: patch.sha)
        let pattern = #"ps-id:\s(?<patchStackId>[\w\d-]+)"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        if let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.utf8.count)) {
            if let patchStackIdRange = Range(match.range(withName: "patchStackId"), in: message) {
                let patchStackIdStr = String(message[patchStackIdRange])
                return UUID(uuidString: patchStackIdStr)
            } else { // matched ps-id but failed to get the range of the capture group
                return nil
            }
        } else { // didn't find match
            return nil
        }
    }

    private func slug(patch: CommitSummary) -> String {
        return patch.summary.replaceCharactersFromSet(characterSet: CharacterSet.alphanumerics.inverted, replacementString: "_").lowercased()
    }
}

extension String {
  func replaceCharactersFromSet(characterSet: CharacterSet, replacementString: String = "") -> String {
    return self.components(separatedBy: characterSet).joined(separator: replacementString)
  }
}
