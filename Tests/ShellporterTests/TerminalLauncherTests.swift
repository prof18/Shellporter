import Foundation
import Testing
@testable import Shellporter

// MARK: - shellEscapedForBash

@Test
func shellEscapedForBash_emptyString() {
    #expect("".shellEscapedForBash() == "''")
}

@Test
func shellEscapedForBash_simpleString() {
    #expect("hello".shellEscapedForBash() == "'hello'")
}

@Test
func shellEscapedForBash_stringWithSpaces() {
    #expect("hello world".shellEscapedForBash() == "'hello world'")
}

@Test
func shellEscapedForBash_stringWithSingleQuote() {
    #expect("it's".shellEscapedForBash() == "'it'\"'\"'s'")
}

@Test
func shellEscapedForBash_stringWithDoubleQuote() {
    #expect("say \"hi\"".shellEscapedForBash() == "'say \"hi\"'")
}

@Test
func shellEscapedForBash_stringWithBackslash() {
    #expect("back\\slash".shellEscapedForBash() == "'back\\slash'")
}

@Test
func shellEscapedForBash_stringWithNewline() {
    #expect("line1\nline2".shellEscapedForBash() == "'line1\nline2'")
}

@Test
func shellEscapedForBash_stringWithTab() {
    #expect("col1\tcol2".shellEscapedForBash() == "'col1\tcol2'")
}

@Test
func shellEscapedForBash_cjkCharacters() {
    #expect("项目/路径".shellEscapedForBash() == "'项目/路径'")
}

@Test
func shellEscapedForBash_multipleSingleQuotes() {
    #expect("a'b'c".shellEscapedForBash() == "'a'\"'\"'b'\"'\"'c'")
}

// MARK: - appleScriptEscaped

@Test
func appleScriptEscaped_emptyString() {
    #expect("".appleScriptEscaped() == "")
}

@Test
func appleScriptEscaped_simpleString() {
    #expect("hello".appleScriptEscaped() == "hello")
}

@Test
func appleScriptEscaped_backslash() {
    #expect("back\\slash".appleScriptEscaped() == "back\\\\slash")
}

@Test
func appleScriptEscaped_doubleQuote() {
    #expect("say \"hi\"".appleScriptEscaped() == "say \\\"hi\\\"")
}

@Test
func appleScriptEscaped_newline() {
    #expect("line1\nline2".appleScriptEscaped() == "line1\\nline2")
}

@Test
func appleScriptEscaped_carriageReturn() {
    #expect("line1\rline2".appleScriptEscaped() == "line1\\rline2")
}

@Test
func appleScriptEscaped_tab() {
    #expect("col1\tcol2".appleScriptEscaped() == "col1\\tcol2")
}

@Test
func appleScriptEscaped_backslashBeforeQuote() {
    // Backslash must be escaped first so \" doesn't become \\\"
    #expect("a\\\"b".appleScriptEscaped() == "a\\\\\\\"b")
}

@Test
func appleScriptEscaped_cjkCharacters() {
    #expect("项目/路径".appleScriptEscaped() == "项目/路径")
}

@Test
func appleScriptEscaped_spaces() {
    #expect("path with spaces".appleScriptEscaped() == "path with spaces")
}

// MARK: - Terminal.app launch script

@Test
func terminalLaunchScript_coldStartTargetsFirstWindow() {
    let path = URL(fileURLWithPath: "/Users/test/My Project")
    let command = "cd \(path.path.shellEscapedForBash())".appleScriptEscaped()

    #expect(
        TerminalLauncher.terminalLaunchScript(path: path) == [
            "tell application \"Terminal\"",
            "if application \"Terminal\" is running then",
            "do script \"\(command)\"",
            "else",
            "reopen",
            "set waitAttempts to 0",
            "repeat while ((count of windows) = 0 and waitAttempts < 40)",
            "delay 0.05",
            "set waitAttempts to waitAttempts + 1",
            "end repeat",
            "if (count of windows) > 0 then",
            "do script \"\(command)\" in front window",
            "else",
            "do script \"\(command)\"",
            "end if",
            "end if",
            "activate",
            "end tell",
        ]
    )
}
