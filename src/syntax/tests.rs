use super::*;

/// The colored parts of `line` (in a file with every comment), as their
/// text and kind, in the order they're colored.
fn parts(line: &str) -> Vec<(String, Kind)> {
    parts_in(line, State::Code, Comments::ALL).0
}

/// The colored parts of `line`, starting in `state`, and the state it ends
/// in.
fn parts_in(line: &str, state: State, comments: Comments) -> (Vec<(String, Kind)>, State) {
    let units: Vec<u16> = line.encode_utf16().collect();
    let (spans, state) = spans(&units, state, comments);
    let parts = spans
        .iter()
        .map(|s| (String::from_utf16(&units[s.start..s.end]).unwrap(), s.kind))
        .collect();
    (parts, state)
}

/// The texts of the parts of `line` that are a `kind`.
fn of(line: &str, kind: Kind) -> Vec<String> {
    parts(line)
        .into_iter()
        .filter(|(_, k)| *k == kind)
        .map(|(text, _)| text)
        .collect()
}

fn strings(line: &str) -> Vec<String> {
    of(line, Kind::String)
}

#[test]
fn test_strings() {
    assert_eq!(
        parts(r#"let s = "a \"b\" c";"#),
        [
            (r#""a \"b\" c""#.to_string(), Kind::String),
            (r#"\""#.to_string(), Kind::Escape),
            (r#"\""#.to_string(), Kind::Escape),
        ]
    );
    assert_eq!(strings(r#"x = "" + "y""#), [r#""""#, r#""y""#]);
    // One that doesn't end on its line isn't one.
    assert_eq!(strings(r#"say "hi"#), Vec::<String>::new());
    // Markdown's code, with no escapes.
    assert_eq!(
        parts(r"run `a\b` now"),
        [("`a\\b`".to_string(), Kind::String)]
    );
    assert_eq!(
        strings(r#""héllo" 'naïve' "🍄""#),
        [r#""héllo""#, "'naïve'", r#""🍄""#]
    );
}

#[test]
fn test_single_quotes() {
    assert_eq!(strings("it's 'x' and don't"), ["'x'"]);
    assert_eq!(strings("the users' files, 'quoted'"), ["'quoted'"]);
    assert_eq!(strings("'It's fine' they said"), Vec::<String>::new());
    assert_eq!(strings("café's 'menu'"), ["'menu'"]);
    assert_eq!(strings(r"'it\'s'"), [r"'it\'s'"]);
    // Rust's lifetimes, and its characters.
    assert_eq!(strings("fn f<'a>(x: &'a str) -> char { 'b' }"), ["'b'"]);
    assert_eq!(
        strings("impl<'a> Foo<'a> for Bar<'a> {}"),
        Vec::<String>::new()
    );
    // Python's prefixes, not a word's end.
    assert_eq!(
        strings(r"f'{x}' + rb'\d' + B'x'"),
        ["'{x}'", r"'\d'", "'x'"]
    );
    assert_eq!(strings("Bob's and Tom's"), Vec::<String>::new());
}

#[test]
fn test_numbers() {
    assert_eq!(
        of(
            "x = 42 + 3.14 - 1e-9 * 0xff_ff + 0b101 - 1_000",
            Kind::Number
        ),
        ["42", "3.14", "1e-9", "0xff_ff", "0b101", "1_000"]
    );
    assert_eq!(
        of("version 1.2.3 at 192.168.0.1", Kind::Number),
        ["1.2.3", "192.168.0.1"]
    );
    // A unit isn't colored, nor what only starts with digits, nor digits
    // in a word.
    assert_eq!(of("10px 2nd 100ms", Kind::Number), ["10", "2", "100"]);
    assert_eq!(of("3f2a9c utf8 x2 a_1 0x", Kind::Number), ["0"]);
    assert_eq!(of("1..10 (-5) #123", Kind::Number), ["1", "10", "5", "123"]);
    // Not in a string.
    assert_eq!(of(r#""42" 7"#, Kind::Number), ["7"]);
}

#[test]
fn test_line_comments() {
    assert_eq!(of("x = 1 // one 'two'", Kind::Comment), ["// one 'two'"]);
    assert_eq!(of("/// docs", Kind::Comment), ["/// docs"]);
    assert_eq!(of("f();// x", Kind::Comment), ["// x"]);
    assert_eq!(
        of(r#"s = "// not" // but this"#, Kind::Comment),
        ["// but this"]
    );
    assert_eq!(of("a = b # c", Kind::Comment), ["# c"]);
    assert_eq!(of("# comment", Kind::Comment), ["# comment"]);
    assert_eq!(of("#", Kind::Comment), ["#"]);
    assert_eq!(of("## more", Kind::Comment), ["## more"]);
    assert_eq!(of("#---", Kind::Comment), ["#---"]);
    assert_eq!(of("#!/bin/sh", Kind::Comment), ["#!/bin/sh"]);
    // Not a URL's slashes, nor a `#` before a word.
    assert!(of("see https://x.com", Kind::Comment).is_empty());
    for line in [
        "#include <x.h>",
        "#[derive(Debug)]",
        "#![allow(x)]",
        "color: #fff",
        "fixes #12",
        "a#b",
        r##""# no""##,
    ] {
        assert!(of(line, Kind::Comment).is_empty(), "{line}");
    }
}

#[test]
fn test_block_comments() {
    assert_eq!(of("a /* b */ c", Kind::Comment), ["/* b */"]);
    assert_eq!(of("f(/* x */ 1)", Kind::Comment), ["/* x */"]);
    assert_eq!(of("<!-- note --> text", Kind::Comment), ["<!-- note -->"]);
    // Not a glob.
    assert!(of("ls src/*.rs", Kind::Comment).is_empty());

    let (parts, state) = parts_in("x = 1 /* starts", State::Code, Comments::ALL);
    assert_eq!(
        parts,
        [
            ("1".to_string(), Kind::Number),
            ("/* starts".to_string(), Kind::Comment)
        ]
    );
    assert_eq!(state, State::Slashes);
    let (parts, state) = parts_in("goes on 'x'", State::Slashes, Comments::ALL);
    assert_eq!(parts, [("goes on 'x'".to_string(), Kind::Comment)]);
    assert_eq!(state, State::Slashes);
    let (parts, state) = parts_in("ends */ y = 2", State::Slashes, Comments::ALL);
    assert_eq!(
        parts,
        [
            ("ends */".to_string(), Kind::Comment),
            ("2".to_string(), Kind::Number)
        ]
    );
    assert_eq!(state, State::Code);
    // A `/*` right after it opens one, but `/*/` doesn't close it.
    assert_eq!(
        parts_in("/*/", State::Code, Comments::ALL).1,
        State::Slashes
    );
    let (_, state) = parts_in("<!-- a", State::Code, Comments::ALL);
    assert_eq!(state, State::Markup);
    assert_eq!(
        parts_in("b */ -->", State::Markup, Comments::ALL).1,
        State::Code
    );

    for number in [-1, 0, 1, 2] {
        assert_eq!(State::from_number(number).number(), number.max(0));
    }
}

#[test]
fn test_comments_of() {
    assert_eq!(
        Comments::of("/a/README.md"),
        Comments {
            hash: false,
            slashes: true
        }
    );
    assert_eq!(
        Comments::of("Notes.MARKDOWN"),
        Comments {
            hash: false,
            slashes: true
        }
    );
    assert_eq!(
        Comments::of("x.py"),
        Comments {
            hash: true,
            slashes: false
        }
    );
    for name in ["main.rs", "Makefile", ".zshrc", "", "notes.txt"] {
        assert_eq!(Comments::of(name), Comments::ALL, "{name}");
    }
    let markdown = Comments::of("README.md");
    assert!(parts_in("# Title", State::Code, markdown).0.is_empty());
    assert_eq!(parts_in("a // b", State::Code, Comments::of("x.py")).0, []);
    assert_eq!(
        parts_in("a /* b", State::Code, Comments::of("x.py")).1,
        State::Code
    );
}

#[test]
fn test_urls() {
    assert_eq!(
        of("see https://example.com/a?b=c.", Kind::Url),
        ["https://example.com/a?b=c"]
    );
    assert_eq!(
        of("(https://en.wikipedia.org/wiki/A_(B)), and", Kind::Url),
        ["https://en.wikipedia.org/wiki/A_(B)"]
    );
    assert_eq!(
        of("<https://x.com/a> [x](http://y.org)", Kind::Url),
        ["https://x.com/a", "http://y.org"]
    );
    assert_eq!(
        of("www.example.com/x, file:///tmp/a", Kind::Url),
        ["www.example.com/x", "file:///tmp/a"]
    );
    assert_eq!(of("**https://x.com**", Kind::Url), ["https://x.com"]);
    // Over the string it's in.
    assert_eq!(
        parts(r#"u = "https://x.com""#),
        [
            (r#""https://x.com""#.to_string(), Kind::String),
            ("https://x.com".to_string(), Kind::Url),
        ]
    );
    for line in ["a_https://b", "https://", "a://", "nowww.x"] {
        assert!(of(line, Kind::Url).is_empty(), "{line}");
    }
}

#[test]
fn test_paths() {
    let paths = |line: &str| of(line, Kind::Path);
    assert_eq!(paths("cd /usr/local/bin"), ["/usr/local/bin"]);
    assert_eq!(paths("~/projects/koil and ~/"), ["~/projects/koil", "~/"]);
    assert_eq!(paths("./run.sh ../x .\\y"), ["./run.sh", "../x", ".\\y"]);
    assert_eq!(
        paths(r"C:\Users\me\x.txt or D:/data"),
        [r"C:\Users\me\x.txt", "D:/data"]
    );
    assert_eq!(paths("src/main.rs:12:5: error"), ["src/main.rs"]);
    assert_eq!(
        paths("a/b/c, docs/ and .github/workflows/x.yml."),
        ["a/b/c", "docs/", ".github/workflows/x.yml"]
    );
    assert_eq!(paths("cmd 2>/dev/null"), ["/dev/null"]);
    assert_eq!(
        paths("PATH=/usr/bin:/bin --dir=/tmp"),
        ["/usr/bin", "/bin", "/tmp"]
    );
    assert_eq!(paths(r"~/my\ dir/x"), [r"~/my\ dir/x"]);
    assert_eq!(
        paths("see (src/a.rs) and [b](lib/b.rs)"),
        ["src/a.rs", "lib/b.rs"]
    );
    assert_eq!(paths("/tmp/1.txt"), ["/tmp/1.txt"]);
    // A `\` is a name's end only in a Windows path.
    assert_eq!(paths(r#"printf("/tmp/x\n")"#), ["/tmp/x"]);
    // Over the string or comment it's in.
    assert_eq!(
        parts(r#"import "./foo.js" // see ~/x"#),
        [
            (r#""./foo.js""#.to_string(), Kind::String),
            ("// see ~/x".to_string(), Kind::Comment),
            ("./foo.js".to_string(), Kind::Path),
            ("~/x".to_string(), Kind::Path),
        ]
    );
    for line in [
        "and/or km/h I/O TCP/IP w/ w/o n/a",
        "1/2 10/12/2026 a//b x / 2",
        "text/plain origin/main",
        "</div> <br/> a />",
        "// comment /* c */ */",
        "f(x)/2 /\\d+/ a/",
    ] {
        assert!(paths(line).is_empty(), "{line}: {:?}", paths(line));
    }
}

#[test]
fn test_long_line() {
    let line = format!("{}\"x\"", " ".repeat(MAX_LENGTH));
    assert!(parts(&line).is_empty());
    let line = format!("\"{}\"", "x".repeat(MAX_LENGTH));
    assert!(parts(&line).is_empty());
}

#[test]
fn test_apart() {
    let drawn = |line: &str| {
        let units: Vec<u16> = line.encode_utf16().collect();
        apart(&spans(&units, State::Code, Comments::ALL).0)
            .iter()
            .map(|s| (String::from_utf16(&units[s.start..s.end]).unwrap(), s.kind))
            .collect::<Vec<_>>()
    };
    let part = |text: &str, kind| (text.to_string(), kind);
    assert_eq!(
        drawn(r#"app="$root/target/Koil.app" # in ~/x now"#),
        [
            part(r#"""#, Kind::String),
            part("$root/target/Koil.app", Kind::Path),
            part(r#"""#, Kind::String),
            part("# in ", Kind::Comment),
            part("~/x", Kind::Path),
            part(" now", Kind::Comment),
        ]
    );
    // Escapes side by side are one part.
    assert_eq!(
        drawn(r#"s = "a\n\tb" + 12"#),
        [
            part(r#""a"#, Kind::String),
            part(r"\n\t", Kind::Escape),
            part(r#"b""#, Kind::String),
            part("12", Kind::Number),
        ]
    );
    assert_eq!(drawn("nothing here"), []);
}
