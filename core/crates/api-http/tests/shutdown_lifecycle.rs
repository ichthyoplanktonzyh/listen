//! The sidecar must never outlive the desktop app, by either exit route.
//!
//! On a clean quit the app sends SIGINT from `dispose()` and does not await
//! the result. On a crash, a force quit, or any SIGKILL it sends nothing at
//! all — so the sidecar also watches for its parent disappearing. Each route
//! that fails leaks a process holding a database connection and a port.

#![cfg(unix)]

use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

/// A throwaway HOME so every path the sidecar derives — database, caches,
/// model roots — stays out of the developer's real profile.
fn temp_home(label: &str) -> PathBuf {
    let home = std::env::temp_dir().join(format!("llp-{label}-{}", std::process::id()));
    fs::create_dir_all(&home).expect("failed to create the temp home");
    home
}

/// True while `pid` names a live process. Signal 0 performs the permission and
/// existence checks without delivering anything.
fn alive(pid: i32) -> bool {
    // SAFETY: `kill` with signal 0 has no effect beyond reporting existence.
    unsafe { libc::kill(pid, 0) == 0 }
}

fn read_pid(path: &Path, deadline: Duration) -> i32 {
    let until = Instant::now() + deadline;
    while Instant::now() < until {
        if let Ok(text) = fs::read_to_string(path)
            && let Ok(pid) = text.trim().parse::<i32>()
            && alive(pid)
        {
            return pid;
        }
        sleep(Duration::from_millis(100));
    }
    panic!("sidecar never reported a pid at {}", path.display());
}

/// Runs the sidecar under an intermediate shell so the test can SIGKILL its
/// parent — the shell stands in for the desktop app being force-quit.
fn spawn_under_shell(home: &Path, pidfile: &Path) -> Child {
    let binary = env!("CARGO_BIN_EXE_api-http");
    Command::new("/bin/sh")
        .arg("-c")
        .arg(format!(
            "'{binary}' >/dev/null 2>&1 & echo $! > '{pidfile}'; sleep 120",
            pidfile = pidfile.display(),
        ))
        .env("HOME", home)
        .env("LLPLAYERNEXT_DB", home.join("test.sqlite"))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn the intermediate shell")
}

#[test]
fn sidecar_exits_after_its_parent_is_killed() {
    let home = temp_home("orphan");
    let pidfile = home.join("sidecar.pid");

    let mut parent = spawn_under_shell(&home, &pidfile);
    let sidecar = read_pid(&pidfile, Duration::from_secs(30));

    // A watchdog that fires while the parent is healthy would be worse than
    // the leak it replaces, so pin that down before killing anything.
    sleep(Duration::from_secs(4));
    assert!(
        alive(sidecar),
        "sidecar exited while its parent was still running"
    );

    // SIGKILL: the parent gets no chance to clean up, exactly like a crash.
    parent.kill().expect("failed to kill the parent shell");
    parent.wait().expect("failed to reap the parent shell");

    // Full-workspace low-memory CI can briefly starve this process while other
    // integration binaries link/start. Keep the assertion bounded but allow
    // enough scheduling headroom that it measures lifecycle, not host load.
    let until = Instant::now() + Duration::from_secs(45);
    while Instant::now() < until {
        if !alive(sidecar) {
            let _ = fs::remove_dir_all(&home);
            return;
        }
        sleep(Duration::from_millis(200));
    }

    // SAFETY: cleaning up a pid this test created, so the failure does not
    // leak the very process it is complaining about.
    unsafe { libc::kill(sidecar, libc::SIGKILL) };
    let _ = fs::remove_dir_all(&home);
    panic!("sidecar outlived its parent by more than 45s");
}

#[test]
fn sidecar_shuts_down_gracefully_on_sigint() {
    let home = temp_home("sigint");
    let mut child = Command::new(env!("CARGO_BIN_EXE_api-http"))
        .env("HOME", &home)
        .env("LLPLAYERNEXT_DB", home.join("test.sqlite"))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn the sidecar");

    // Held for the whole test: dropping the pipe early would break the
    // sidecar's own stdout and end it for the wrong reason.
    let mut stdout = BufReader::new(child.stdout.take().expect("piped stdout"));
    let mut handshake = String::new();
    stdout
        .read_line(&mut handshake)
        .expect("failed to read the handshake");
    assert!(
        handshake.contains("api.started"),
        "unexpected handshake: {handshake}"
    );

    // What `LocalApi.requestStop` sends from the app's dispose().
    // SAFETY: signalling a child this test spawned.
    unsafe { libc::kill(child.id() as i32, libc::SIGINT) };

    let until = Instant::now() + Duration::from_secs(20);
    while Instant::now() < until {
        if let Some(status) = child.try_wait().expect("failed to poll the child") {
            // A zero code proves the graceful path ran. An unhandled SIGINT
            // would have terminated the process by signal instead, leaving the
            // database to be recovered rather than closed.
            assert_eq!(
                status.code(),
                Some(0),
                "sidecar did not exit through its graceful shutdown"
            );
            let _ = fs::remove_dir_all(&home);
            return;
        }
        sleep(Duration::from_millis(100));
    }

    // Reap it here so the failure does not also leak the process it is about.
    let _ = child.kill();
    let _ = child.wait();
    let _ = fs::remove_dir_all(&home);
    panic!("sidecar ignored SIGINT for more than 20s");
}
