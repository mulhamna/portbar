#if DEBUG
import Foundation

// ponytail: assert-based smoke checks instead of an XCTest target — this app has no
// test bundle and one wasn't worth adding for a handful of pure parsers. Runs at
// launch in Debug only. Add cases here when a parser grows a new edge.
enum SelfCheck {
    static func run() {
        checkParsePs()
        checkColumnSanitizing()
    }

    private static func checkColumnSanitizing() {
        // No stored layout, or an empty one, falls back to the shipped default.
        assert(PortColumn.sanitized(nil) == PortColumn.defaultLayout)
        assert(PortColumn.sanitized([]) == PortColumn.defaultLayout)

        // A downgrade sees raw values this build doesn't know — drop them, keep order.
        assert(PortColumn.sanitized(["port", "gpu", "process", "tools"])
               == [.port, .process, .tools])

        // Nothing recognisable at all is treated as no layout.
        assert(PortColumn.sanitized(["gpu", "nonsense"]) == PortColumn.defaultLayout)

        // Duplicates collapse to their first position.
        assert(PortColumn.sanitized(["port", "process", "port", "tools"])
               == [.port, .process, .tools])

        // A hand-edited default that dropped the locked columns gets them back.
        let repaired = PortColumn.sanitized(["process", "uptime"])
        assert(repaired.contains(.port) && repaired.contains(.tools),
               "locked columns not restored: \(repaired)")
    }

    private static func checkParsePs() {
        let scanner = PortScanner()

        // pid ppid stat %cpu rss %mem etime comm — comm last so a path with spaces
        // stays intact instead of shifting every field after it.
        let output = """
        48213     1 S      2.4  145408  0.9    04:12:33 /usr/local/bin/node
         1129     1 Ss     0.0    2112  0.0 12-07:41:02 /Applications/My App/Contents/MacOS/My App
        """

        let parsed = scanner.parsePs(output)
        assert(parsed.count == 2, "expected 2 rows, got \(parsed.count)")

        let node = parsed[48213]
        assert(node?.name == "/usr/local/bin/node", "node name: \(node?.name ?? "nil")")
        assert(node?.ppid == 1)
        assert(node?.stat == "S")
        assert(node?.cpu == 2.4, "node cpu: \(node?.cpu ?? -1)")
        assert(node?.rss == 145408, "node rss: \(node?.rss ?? -1)")
        assert(node?.memPercent == 0.9)
        assert(parseEtime(node?.etime ?? "") == TimeInterval(15153))   // 04:12:33

        // The spaces-in-path case: everything before comm must still line up.
        let spaced = parsed[1129]
        assert(spaced?.name == "/Applications/My App/Contents/MacOS/My App",
               "spaced name: \(spaced?.name ?? "nil")")
        assert(spaced?.stat == "Ss", "spaced stat: \(spaced?.stat ?? "nil")")
        assert(spaced?.rss == 2112)
        assert(parseEtime(spaced?.etime ?? "") == TimeInterval(1064462))  // 12-07:41:02

        // Short/garbage lines are dropped, not crashed on.
        assert(scanner.parsePs("garbage\n\n123 456\n").isEmpty)
    }
}
#endif
