//! The sidecar must not outlive the process that spawned it.
//!
//! The desktop app closes it from `dispose()`, which never runs on a crash,
//! a force quit, or any SIGKILL. Without a watchdog each such exit leaks a
//! process holding a database connection and a port.

#![cfg(unix)]

use std::fs;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

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
        // Keep every path the sidecar derives inside the temp home so the test
        // never touches the developer's real database or caches.
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
    let home = std::env::temp_dir().join(format!("llp-orphan-{}", std::process::id()));
    fs::create_dir_all(&home).expect("failed to create the temp home");
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

    let until = Instant::now() + Duration::from_secs(20);
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
    panic!("sidecar outlived its parent by more than 20s");
}
