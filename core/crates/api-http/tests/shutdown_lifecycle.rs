//! The sidecar must never outlive the desktop app, by either exit route.
//!
//! On a clean quit the app sends SIGINT from `dispose()` and does not await
//! the result. On a crash, a force quit, or any SIGKILL it sends nothing at
//! all — so the sidecar also watches for its parent disappearing. Each route
//! that fails leaks a process holding a database connection and a port.
//!
//! The orphan test drives the sidecar through an intermediate shell that
//! stands in for the desktop app. The shell is spawned with an explicit
//! `exec` subshell so the sidecar's parent is deterministically the shell —
//! a bare `&` job can be routed through an extra subshell that exits before
//! the sidecar captures its parent identity, which would leave the watchdog
//! deliberately disabled (the sidecar would look daemonized). The test also
//! waits for the `api.started` handshake before killing the shell, so the
//! parent identity is always captured before the orphan check starts.
//!
//! The handshake is read from a file with a bounded deadline instead of a
//! blocking pipe read: the sidecar's stdout is redirected into the temp
//! HOME, and a polling helper parses the first complete `api.started` line.
//! Every child and every temp directory is owned by an RAII guard, so each
//! exit path — success, assertion failure, parse failure, timeout or panic —
//! still kills and reaps the processes and removes the directory.

#![cfg(unix)]

use std::fs;
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

/// A process identity: the pid plus the boot-relative instant the process
/// started. Binding liveness checks to the identity means a pid recycled by
/// the kernel is never mistaken for the sidecar this test actually spawned.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ProcessIdentity {
    pid: i32,
    start: u64,
}

/// The current facts about a process, or `None` when no such process exists.
/// A zombie still exists and is reported with `zombie: true`.
struct ProcessInfo {
    identity: ProcessIdentity,
    zombie: bool,
}

/// Probes the kernel for the process `pid`, if it exists.
///
/// Only a report of exactly the full structure size is accepted: a partial
/// or zeroed buffer must not be read as a valid identity.
#[cfg(target_os = "macos")]
fn probe(pid: i32) -> Option<ProcessInfo> {
    // SAFETY: `proc_pidinfo` fills `info` only up to the size passed in, and
    // the buffer is fully zero-initialized first.
    let mut info = unsafe { std::mem::zeroed::<libc::proc_bsdinfo>() };
    let expected = std::mem::size_of::<libc::proc_bsdinfo>() as libc::c_int;
    let written = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDTBSDINFO,
            0,
            &mut info as *mut libc::proc_bsdinfo as *mut libc::c_void,
            expected,
        )
    };
    if written != expected {
        return None;
    }
    Some(ProcessInfo {
        identity: ProcessIdentity {
            pid,
            start: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
        },
        zombie: info.pbi_status == libc::SZOMB,
    })
}

/// Probes the process table for `pid` on Linux, where the start time and the
/// zombie state come from `/proc/<pid>/stat`.
#[cfg(all(unix, not(target_os = "macos")))]
fn probe(pid: i32) -> Option<ProcessInfo> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let (_, rest) = stat
        .rfind(") ")
        .map(|at| stat.split_at(at + 1))
        .unwrap_or(("", ""));
    let mut fields = rest.split_whitespace();
    let state = fields.next()?;
    let start_ticks: u64 = fields.nth(18)?.parse().ok()?;
    Some(ProcessInfo {
        identity: ProcessIdentity {
            pid,
            start: start_ticks,
        },
        zombie: state == "Z",
    })
}

/// True while `identity` still names the same, still-executing process.
///
/// A zombie no longer executes: it holds no database connection, listens on
/// no port and will never run again, so it counts as gone for the watchdog
/// assertions. A pid that has been recycled fails the start-time check.
fn alive(identity: ProcessIdentity) -> bool {
    let Some(current) = probe(identity.pid) else {
        return false;
    };
    !current.zombie && current.identity.start == identity.start
}

/// Waits for the shell to write the sidecar's pid and returns its identity.
fn read_sidecar_identity(path: &Path, deadline: Duration) -> ProcessIdentity {
    let until = Instant::now() + deadline;
    while Instant::now() < until {
        if let Ok(text) = fs::read_to_string(path)
            && let Ok(pid) = text.trim().parse::<i32>()
            && let Some(info) = probe(pid)
            && !info.zombie
        {
            return info.identity;
        }
        sleep(Duration::from_millis(100));
    }
    panic!("sidecar never reported a pid at {}", path.display());
}

/// Waits for the first complete `api.started` line in `path`, within a
/// bounded deadline, and returns its parsed JSON.
///
/// The sidecar's stdout is redirected to `path`, so no reader thread and no
/// blocking pipe read is involved: an incomplete trailing line simply fails
/// to parse and is skipped until the next poll.
fn wait_for_handshake(path: &Path, deadline: Duration) -> serde_json::Value {
    let until = Instant::now() + deadline;
    while Instant::now() < until {
        if let Ok(text) = fs::read_to_string(path) {
            for line in text.lines() {
                if let Ok(value) = serde_json::from_str::<serde_json::Value>(line.trim())
                    && value["event"] == "api.started"
                {
                    return value;
                }
            }
        }
        sleep(Duration::from_millis(50));
    }
    panic!(
        "sidecar never printed the api.started handshake to {}",
        path.display()
    );
}

/// Best-effort reaper for a directly spawned child.
///
/// On every exit path — normal return, assertion failure, parse failure,
/// timeout or panic — the guard kills the child if it is still running and
/// then reaps it, so a failing test cannot leak the process.
struct ChildGuard {
    child: Option<Child>,
}

impl ChildGuard {
    fn new(child: Child) -> Self {
        Self { child: Some(child) }
    }

    /// SIGKILLs and reaps the child now.
    fn kill_and_reap(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }

    /// Polls the child for an exit status, reaping it when it has exited.
    fn try_wait(&mut self) -> Option<ExitStatus> {
        let child = self.child.as_mut()?;
        match child.try_wait().expect("failed to poll the child") {
            Some(status) => {
                self.child = None;
                Some(status)
            }
            None => None,
        }
    }

    /// Blocks until the child has exited and reaps it.
    fn reap(&mut self) -> ExitStatus {
        let mut child = self.child.take().expect("child has already been reaped");
        child.wait().expect("failed to wait for the child")
    }
}

impl Drop for ChildGuard {
    fn drop(&mut self) {
        self.kill_and_reap();
    }
}

/// Signals the orphan sidecar on every exit path, but only while the pid
/// still names the very process this test spawned: a recycled pid must not
/// be killed by the cleanup.
struct OrphanSidecarGuard {
    identity: ProcessIdentity,
}

impl OrphanSidecarGuard {
    fn new(identity: ProcessIdentity) -> Self {
        Self { identity }
    }
}

impl Drop for OrphanSidecarGuard {
    fn drop(&mut self) {
        if let Some(current) = probe(self.identity.pid)
            && !current.zombie
            && current.identity.start == self.identity.start
        {
            // SAFETY: the pid still names the sidecar this test spawned.
            unsafe { libc::kill(self.identity.pid, libc::SIGKILL) };
        }
    }
}

/// Runs the sidecar under an intermediate shell so the test can SIGKILL its
/// parent — the shell stands in for the desktop app being force-quit.
///
/// The subshell is an explicit `exec`, so the pid written by the shell is
/// deterministically the sidecar itself and the sidecar's parent is the shell
/// (see the module comment about the double-fork race). The sidecar's stdout
/// is redirected to `handshake_file`, which the test polls with a deadline.
fn spawn_under_shell(home: &Path, pidfile: &Path, handshake_file: &Path) -> Child {
    let binary = env!("CARGO_BIN_EXE_api-http");
    Command::new("/bin/sh")
        .arg("-c")
        .arg(format!(
            "( exec '{binary}' >'{handshake}' 2>/dev/null ) & echo $! > '{pidfile}'; sleep 120",
            handshake = handshake_file.display(),
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
    let home = tempfile::TempDir::new().expect("failed to create the temp home");
    let pidfile = home.path().join("sidecar.pid");
    let handshake_file = home.path().join("sidecar.out");

    let parent = spawn_under_shell(home.path(), &pidfile, &handshake_file);
    let mut parent_guard = ChildGuard::new(parent);
    let sidecar = read_sidecar_identity(&pidfile, Duration::from_secs(30));
    let _sidecar_guard = OrphanSidecarGuard::new(sidecar);

    // The handshake is printed after the parent identity has been captured,
    // so once it arrives killing the shell exercises the orphan watchdog
    // instead of racing the sidecar's own startup.
    let handshake = wait_for_handshake(&handshake_file, Duration::from_secs(30));
    assert_eq!(
        handshake["event"], "api.started",
        "unexpected handshake: {handshake}"
    );
    assert_eq!(handshake["api_version"], api_http::API_VERSION);
    assert_eq!(handshake["contract_version"], api_http::CONTRACT_VERSION);
    assert_eq!(handshake["runtime_version"], env!("CARGO_PKG_VERSION"));

    // A watchdog that fires while the parent is healthy would be worse than
    // the leak it replaces, so pin that down before killing anything.
    sleep(Duration::from_secs(4));
    assert!(
        alive(sidecar),
        "sidecar exited while its parent was still running"
    );

    // SIGKILL: the parent gets no chance to clean up, exactly like a crash.
    parent_guard.kill_and_reap();

    // Full-workspace low-memory CI can briefly starve this process while other
    // integration binaries link/start. Keep the assertion bounded but allow
    // enough scheduling headroom that it measures lifecycle, not host load.
    let until = Instant::now() + Duration::from_secs(45);
    while Instant::now() < until {
        if !alive(sidecar) {
            return;
        }
        sleep(Duration::from_millis(200));
    }
    panic!("sidecar outlived its parent by more than 45s");
}

#[test]
fn sidecar_shuts_down_gracefully_on_sigint() {
    let home = tempfile::TempDir::new().expect("failed to create the temp home");
    let handshake_file = home.path().join("sidecar.out");
    let stdout = fs::File::create(&handshake_file).expect("failed to create the handshake file");
    let child = Command::new(env!("CARGO_BIN_EXE_api-http"))
        .env("HOME", home.path())
        .env("LLPLAYERNEXT_DB", home.path().join("test.sqlite"))
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn the sidecar");
    let sidecar_pid = child.id() as i32;
    let mut sidecar_guard = ChildGuard::new(child);

    let handshake = wait_for_handshake(&handshake_file, Duration::from_secs(30));
    assert_eq!(
        handshake["event"], "api.started",
        "unexpected handshake: {handshake}"
    );
    assert_eq!(handshake["api_version"], api_http::API_VERSION);
    assert_eq!(handshake["contract_version"], api_http::CONTRACT_VERSION);
    assert_eq!(handshake["runtime_version"], env!("CARGO_PKG_VERSION"));

    // What `LocalApi.requestStop` sends from the app's dispose().
    // SAFETY: signalling a child this test spawned.
    unsafe { libc::kill(sidecar_pid, libc::SIGINT) };

    let until = Instant::now() + Duration::from_secs(20);
    while Instant::now() < until {
        if let Some(status) = sidecar_guard.try_wait() {
            // A zero code proves the graceful path ran. An unhandled SIGINT
            // would have terminated the process by signal instead, leaving the
            // database to be recovered rather than closed.
            assert_eq!(
                status.code(),
                Some(0),
                "sidecar did not exit through its graceful shutdown"
            );
            return;
        }
        sleep(Duration::from_millis(100));
    }
    panic!("sidecar ignored SIGINT for more than 20s");
}

#[test]
fn a_zombie_is_not_an_executing_sidecar() {
    // An un-reaped child of this test process lingers as a zombie: the kernel
    // still counts it (`kill(pid, 0)` succeeds) but it no longer executes, so
    // the liveness probe must treat it as gone.
    let child = Command::new("/bin/sh")
        .arg("-c")
        .arg("sleep 0.3; exit 0")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn the zombie");
    let pid = child.id() as i32;
    let mut child_guard = ChildGuard::new(child);

    let identity = probe(pid)
        .expect("child must be probe-able right after spawn")
        .identity;
    assert!(
        alive(identity),
        "the child should be running right after spawn"
    );

    // Wait for the child to exit without reaping it: it stays in the table
    // as a zombie under this test process.
    let until = Instant::now() + Duration::from_secs(10);
    while alive(identity) {
        assert!(
            Instant::now() < until,
            "child never exited before the deadline"
        );
        sleep(Duration::from_millis(10));
    }

    // Still present in the process table (a zombie)…
    // SAFETY: signal 0 on this test's own un-reaped child only reports
    // existence.
    assert_eq!(
        unsafe { libc::kill(pid, 0) },
        0,
        "the zombie should still be visible to the kernel"
    );
    // …but no longer executing, so it must not count as a running sidecar.
    assert!(
        !alive(identity),
        "a zombie must not count as an executing sidecar"
    );
    let _ = child_guard.reap();
}

#[test]
fn identity_binding_rejects_forged_and_reaped_processes() {
    // A live process — this test process itself — is alive.
    let self_identity = probe(std::process::id() as i32)
        .expect("the test process itself should exist")
        .identity;
    assert!(
        alive(self_identity),
        "the test process itself should be alive"
    );

    // The same pid with a different start time is not the same process.
    let forged = ProcessIdentity {
        pid: self_identity.pid,
        start: self_identity.start + 1,
    };
    assert!(
        !alive(forged),
        "a mismatched start time must fail the identity check"
    );

    // A process that has been reaped is deterministically not alive: right
    // after `wait()` the table entry is gone, no pid-recycle wait required.
    let child = Command::new("/bin/sh")
        .arg("-c")
        .arg("sleep 0.2; exit 0")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to spawn the short-lived child");
    let pid = child.id() as i32;
    let mut child_guard = ChildGuard::new(child);

    let until = Instant::now() + Duration::from_secs(5);
    let short_lived = loop {
        if let Some(info) = probe(pid) {
            break info.identity;
        }
        assert!(
            Instant::now() < until,
            "short-lived child never became probe-able"
        );
        sleep(Duration::from_millis(10));
    };
    assert!(
        alive(short_lived),
        "the short-lived child should be running right after spawn"
    );

    let _ = child_guard.reap();
    assert!(
        !alive(short_lived),
        "a reaped process must not count as alive"
    );
}
