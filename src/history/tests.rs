use std::time::{Duration, UNIX_EPOCH};

use koil_core::apply::Undo;

use super::*;

/// An apply made `at` seconds after the epoch, whose undo trashes `path`.
fn applied(at: u64, path: &str) -> Applied {
    Applied {
        time: UNIX_EPOCH + Duration::from_secs(at),
        dir: PathBuf::from("/dir"),
        steps: vec![Undo::Trash(PathBuf::from(path))],
    }
}

#[test]
fn test_merge_new_ones() {
    let (a, b, c) = (applied(1, "/a"), applied(2, "/b"), applied(3, "/c"));
    // `c` applied here, `b` by another Koil, in time order
    let merged = merge(
        &[a.clone(), b.clone()],
        &[a.clone(), c.clone()],
        std::slice::from_ref(&a),
    );
    assert_eq!(vec![a, b, c], merged);
}

#[test]
fn test_merge_undone_ones() {
    let (a, b, c) = (applied(1, "/a"), applied(2, "/b"), applied(3, "/c"));
    let last = [a.clone(), b.clone(), c.clone()];
    // `b` undone here, `c` by another Koil
    let merged = merge(&[a.clone(), b.clone()], &[a.clone(), c.clone()], &last);
    assert_eq!(vec![a], merged);
}

#[test]
fn test_merge_changed_ones() {
    let (a, b) = (applied(1, "/a"), applied(2, "/b"));
    let (a2, b2) = (
        Applied {
            dir: PathBuf::from("/moved"),
            ..a.clone()
        },
        Applied {
            dir: PathBuf::from("/moved"),
            ..b.clone()
        },
    );
    // `a` changed here, `b` by another Koil: each keeps the change
    let merged = merge(&[a.clone(), b2.clone()], &[a2.clone(), b.clone()], &[a, b]);
    assert_eq!(vec![a2, b2], merged);
}

#[test]
fn test_merge_keeps_newest() {
    let ours: Vec<Applied> = (0..KEPT as u64 + 5).map(|i| applied(i, "/a")).collect();
    let merged = merge(&[], &ours, &[]);
    assert_eq!(&ours[5..], merged);
}

#[test]
fn test_two_koils_share_a_file() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("data/history.json");
    let (mut one, mut two) = (History::at(Some(path.clone())), History::at(Some(path)));
    let (mut koil_one, mut koil_two) = (Koil::default(), Koil::default());
    let (a, b) = (applied(1, "/a"), applied(2, "/b"));

    // each sees what the other applied
    koil_one.set_history(vec![a.clone()]);
    one.merge(&mut koil_one);
    koil_two.set_history(vec![b.clone()]);
    two.merge(&mut koil_two);
    assert_eq!([a.clone(), b.clone()], koil_two.history());
    one.merge(&mut koil_one);
    assert_eq!([a.clone(), b.clone()], koil_one.history());

    // and what it undid
    koil_one.set_history(vec![b.clone()]);
    one.merge(&mut koil_one);
    two.merge(&mut koil_two);
    assert_eq!(std::slice::from_ref(&b), koil_two.history());

    // and a new Koil starts with it
    let mut koil = Koil::default();
    History::at(Some(temp.path().join("data/history.json"))).merge(&mut koil);
    assert_eq!([b], koil.history());
}

#[test]
fn test_file_that_cant_be_read() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("history.json");
    let mut history = History::at(Some(path.clone()));
    let mut koil = Koil::default();
    let a = applied(1, "/a");
    koil.set_history(vec![a.clone()]);
    history.merge(&mut koil);

    // half written by something else: not a history whose applies were undone
    fs::write(&path, "[{\"time\":").unwrap();
    history.merge(&mut koil);
    assert_eq!(std::slice::from_ref(&a), koil.history());
    // and once there's more to keep, it's written whole again
    let b = applied(2, "/b");
    koil.set_history(vec![a.clone(), b.clone()]);
    history.merge(&mut koil);
    assert_eq!(Some(vec![a, b]), read(&path));
}
