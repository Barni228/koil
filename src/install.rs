use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

/// Where the `koil` command goes on macOS: a dir on the PATH every shell
/// gets (`/etc/paths`), but root's, so writing in it takes an admin's
/// password. (On Windows, the installer puts Koil's folder on the PATH.)
pub const COMMAND: &str = "/usr/local/bin/koil";

/// The line after `#!/bin/sh` in Koil's script, which tells it from another
/// program's.
const MARK: &str = "# The koil command, which Koil's Settings window installed.";

/// What's at the command's path.
#[derive(Debug, PartialEq, Eq)]
pub enum Status {
    Missing,
    /// This Koil's script.
    Installed,
    /// Another Koil's: one that was moved, or another copy.
    OtherKoil,
    /// Another program.
    Other,
}

impl Status {
    /// As QML has it.
    pub fn name(&self) -> &'static str {
        match self {
            Status::Missing => "missing",
            Status::Installed => "installed",
            Status::OtherKoil => "otherKoil",
            Status::Other => "other",
        }
    }
}

/// The command's script, which runs Koil's binary `exe`. It runs it where
/// it is, rather than being a link to it, so it's in its bundle (whose
/// Dock icon it shows); `exec` gives it the script's stdin and arguments.
/// Nothing takes the script away when Koil is moved or deleted (macOS runs
/// nothing for an app dragged to the Trash), so then it says what to do
/// (`$0` is where it is).
pub fn script(exe: &Path) -> String {
    format!(
        r#"#!/bin/sh
{MARK}
koil={}
if [ ! -x "$koil" ]; then
  echo "koil: Koil isn't at $koil any more." >&2
  echo "If it was moved, install the command again in its Settings window." >&2
  echo "If it was deleted, remove the command: sudo rm $0" >&2
  exit 127
fi
exec "$koil" "$@"
"#,
        sh_quote(exe)
    )
}

/// What's at `command`, for the Koil whose binary is `exe`.
pub fn status(command: &Path, exe: &Path) -> Status {
    match fs::read(command) {
        Ok(bytes) if bytes == script(exe).as_bytes() => Status::Installed,
        Ok(bytes) if bytes.starts_with(format!("#!/bin/sh\n{MARK}\n").as_bytes()) => {
            Status::OtherKoil
        }
        Err(_) if command.symlink_metadata().is_err() => Status::Missing,
        _ => Status::Other,
    }
}

/// Puts the script that runs `exe` at `command`, in place of whatever's
/// there, asking for an admin's password if it must (see `as_admin`).
pub fn install(command: &Path, exe: &Path) -> io::Result<()> {
    let exe_path = exe.to_string_lossy();
    if exe_path.starts_with("/Volumes/") || exe_path.contains("/AppTranslocation/") {
        return Err(io::Error::other(
            "Koil runs from its disk image: move it to Applications first",
        ));
    }
    let text = script(exe);
    let dir = command.parent().unwrap_or(Path::new("/"));
    let written = fs::create_dir_all(dir)
        .and_then(|()| fs::write(command, &text))
        .and_then(|()| fs::set_permissions(command, fs::Permissions::from_mode(0o755)));
    match written {
        Err(err) if err.kind() == io::ErrorKind::PermissionDenied => {
            // Copied from a file of the user's, as root.
            let temp = std::env::temp_dir().join(format!("koil-command.{}", std::process::id()));
            fs::write(&temp, &text)?;
            let copied = as_admin(&format!(
                "/bin/mkdir -p {dir} && /bin/cp {temp} {command} && /bin/chmod 755 {command}",
                dir = sh_quote(dir),
                temp = sh_quote(&temp),
                command = sh_quote(command),
            ));
            let _ = fs::remove_file(&temp);
            copied
        }
        written => written,
    }
}

/// Removes `command`, asking for an admin's password if it must.
pub fn remove(command: &Path) -> io::Result<()> {
    match fs::remove_file(command) {
        Err(err) if err.kind() == io::ErrorKind::PermissionDenied => {
            as_admin(&format!("/bin/rm -f {}", sh_quote(command)))
        }
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(()),
        removed => removed,
    }
}

/// Runs `shell` as root, once the user gives an admin's password in the
/// dialog macOS shows (through `osascript`, as there's no other way left
/// that isn't deprecated). `Interrupted` if they cancel it.
fn as_admin(shell: &str) -> io::Result<()> {
    let script = format!(
        "{} with prompt {} with administrator privileges",
        shell_script(shell),
        apple_quote("Koil wants to change the koil command in /usr/local/bin."),
    );
    let output = Command::new("/usr/bin/osascript")
        .arg("-e")
        .arg(script)
        .output()?;
    if output.status.success() {
        return Ok(());
    }
    // Like `0:94: execution error: User canceled. (-128)`.
    let error = String::from_utf8_lossy(&output.stderr);
    if error.trim_end().ends_with("(-128)") {
        return Err(io::ErrorKind::Interrupted.into());
    }
    let why = error.split("execution error: ").last().unwrap_or(&error);
    Err(io::Error::other(why.trim().to_string()))
}

/// The AppleScript that runs `shell`.
fn shell_script(shell: &str) -> String {
    format!("do shell script {}", apple_quote(shell))
}

/// `text` as an AppleScript string.
fn apple_quote(text: &str) -> String {
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

/// `path` quoted for `sh`, which reads nothing in single quotes but the
/// quote ending them.
fn sh_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use std::io::Write;
    use std::process::Stdio;

    use super::*;

    #[test]
    fn test_script() {
        let exe = Path::new("/Applications/Koil's.app/Contents/MacOS/koil");
        let script = script(exe);
        assert!(script.starts_with(&format!("#!/bin/sh\n{MARK}\n")));
        assert!(script.contains("\nkoil='/Applications/Koil'\\''s.app/Contents/MacOS/koil'\n"));
    }

    #[test]
    fn test_shell_script() {
        // As `as_admin` runs it, but as the user.
        let temp = tempfile::tempdir().unwrap();
        let dir = temp.path().join(r#"it's a "dir" \ x"#);
        let shell = format!("/bin/mkdir -p {} && echo \"$HOME\"", sh_quote(&dir));
        let output = Command::new("/usr/bin/osascript")
            .arg("-e")
            .arg(shell_script(&shell))
            .output()
            .unwrap();
        assert!(output.status.success(), "{output:?}");
        assert!(dir.is_dir());
    }

    #[test]
    fn test_install() {
        let temp = tempfile::tempdir().unwrap();
        let command = temp.path().join("bin/koil");
        let exe = temp.path().join("Koil.app/Contents/MacOS/koil");
        assert_eq!(status(&command, &exe), Status::Missing);
        install(&command, &exe).unwrap();
        assert_eq!(status(&command, &exe), Status::Installed);
        let mode = fs::metadata(&command).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o755);
        assert_eq!(
            status(&command, &temp.path().join("Moved.app/Contents/MacOS/koil")),
            Status::OtherKoil
        );
        // Koil isn't there (yet): the script says so.
        let output = Command::new(&command).output().unwrap();
        assert_eq!(output.status.code(), Some(127));
        let error = String::from_utf8_lossy(&output.stderr);
        assert!(error.starts_with(&format!(
            "koil: Koil isn't at {} any more.\n",
            exe.display()
        )));
        assert!(
            error.ends_with(&format!("sudo rm {}\n", command.display())),
            "{error}"
        );
        // The script runs Koil with what the command was given.
        fs::create_dir_all(exe.parent().unwrap()).unwrap();
        fs::write(&exe, "#!/bin/sh\necho \"$@\"; cat\n").unwrap();
        fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();
        let mut child = Command::new(&command)
            .args(["a b", "+3"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        child.stdin.take().unwrap().write_all(b"piped\n").unwrap();
        let output = child.wait_with_output().unwrap();
        assert_eq!(String::from_utf8_lossy(&output.stdout), "a b +3\npiped\n");
        remove(&command).unwrap();
        assert_eq!(status(&command, &exe), Status::Missing);
        // Nothing to remove.
        remove(&command).unwrap();
        fs::write(&command, "#!/bin/sh\necho other\n").unwrap();
        assert_eq!(status(&command, &exe), Status::Other);
        let dmg = Path::new("/Volumes/Koil/Koil.app/Contents/MacOS/koil");
        assert!(install(&command, dmg).is_err());
        assert_eq!(status(&command, &exe), Status::Other);
    }
}
