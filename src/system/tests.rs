use super::*;

fn app(name: &str, path: &str, default: bool) -> App {
    App {
        name: name.to_string(),
        path: path.to_string(),
        default,
        place: String::new(),
    }
}

fn names(apps: &[App]) -> Vec<&str> {
    apps.iter().map(|app| app.name.as_str()).collect()
}

/// The default first, then by name, case left out, each once.
#[test]
fn apps_sorted() {
    let apps = sorted_apps(vec![
        app("Xcode", "/Applications/Xcode.app", false),
        app("TextEdit", "/System/Applications/TextEdit.app", true),
        app("code", "/Applications/code.app", false),
        app("BBEdit", "/Applications/BBEdit.app", false),
        app("TextEdit", "/System/Applications/TextEdit.app", false),
    ]);
    assert_eq!(names(&apps), ["TextEdit", "BBEdit", "code", "Xcode"]);
    assert!(apps[0].default);
    assert!(apps.iter().skip(1).all(|app| !app.default));
    assert!(apps.iter().all(|app| app.place.is_empty()));
    // A path listed again keeps that it's the default.
    let apps = sorted_apps(vec![
        app("Zed", "/Applications/Zed.app", false),
        app("Zed", "/Applications/Zed.app", true),
        app("Atom", "/Applications/Atom.app", false),
    ]);
    assert_eq!(names(&apps), ["Zed", "Atom"]);
    assert!(apps[0].default);
}

/// Two apps of one name (two versions of one, or two that show one name)
/// show where each is.
#[test]
fn apps_of_one_name() {
    let apps = sorted_apps(vec![
        app("Xcode", "/Volumes/Old/Xcode.app", false),
        app("Pages", "/Applications/Pages Creator Studio.app", false),
        app("Xcode", "/Applications/Xcode.app", false),
        app("Pages", "/Applications/Pages.app", false),
        app("Preview", "/System/Applications/Preview.app", true),
    ]);
    assert_eq!(
        names(&apps),
        ["Preview", "Pages", "Pages", "Xcode", "Xcode"]
    );
    let places: Vec<&str> = apps.iter().map(|app| app.place.as_str()).collect();
    assert_eq!(
        places,
        [
            "",
            "/Applications/Pages Creator Studio.app",
            "/Applications/Pages.app",
            "/Applications/Xcode.app",
            "/Volumes/Old/Xcode.app"
        ]
    );
}

/// A name, then the start of one, then a part of one, case left out.
#[test]
fn apps_named() {
    let apps = sorted_apps(vec![
        app("TextEdit", "/System/Applications/TextEdit.app", true),
        app(
            "Visual Studio Code",
            "/Applications/Visual Studio Code.app",
            false,
        ),
        app("Text", "/Applications/Text.app", false),
        app("Xcode", "/Applications/Xcode.app", false),
    ]);
    assert_eq!(names(&named(&apps, "text")), ["Text"]);
    assert_eq!(names(&named(&apps, "TEXTE")), ["TextEdit"]);
    assert_eq!(names(&named(&apps, "te")), ["TextEdit", "Text"]);
    assert_eq!(
        names(&named(&apps, "code")),
        ["Visual Studio Code", "Xcode"]
    );
    assert_eq!(names(&named(&apps, "studio")), ["Visual Studio Code"]);
    assert_eq!(names(&named(&apps, "/applications/xcode.app")), ["Xcode"]);
}

/// A name no app listed has is an app the system looks for, as typed.
#[test]
fn apps_not_listed() {
    let apps = sorted_apps(vec![app(
        "TextEdit",
        "/System/Applications/TextEdit.app",
        true,
    )]);
    assert_eq!(named(&apps, "Preview"), [app("Preview", "Preview", false)]);
    assert_eq!(
        named(&apps, "/Applications/Foo.app"),
        [app("/Applications/Foo.app", "/Applications/Foo.app", false)]
    );
    assert_eq!(named(&[], "Preview"), [app("Preview", "Preview", false)]);
}
