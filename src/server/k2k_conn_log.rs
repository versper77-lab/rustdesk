//! K2K: local, append-only log of incoming sessions that passed authorization.
//! One JSON object per line in `<config dir>/k2k_connections.log`, newest last.

use base::message_proto::LoginRequest;
use hbb_common::{chrono, config::Config, log};
use serde_derive::Serialize;
use std::{fs::OpenOptions, io::Write, path::PathBuf};

const FILE_NAME: &str = "k2k_connections.log";
const MAX_LINES_RETURNED: usize = 300;

#[derive(Serialize)]
struct Entry<'a> {
    time: String,
    peer_id: &'a str,
    peer_name: &'a str,
    peer_platform: &'a str,
    ip: &'a str,
    kind: &'a str,
}

fn path() -> PathBuf {
    Config::path(FILE_NAME)
}

pub fn record(lr: &LoginRequest, ip: &str, kind: &str) {
    let entry = Entry {
        time: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        peer_id: &lr.my_id,
        peer_name: &lr.my_name,
        peer_platform: &lr.my_platform,
        ip,
        kind,
    };
    let Ok(line) = serde_json::to_string(&entry) else {
        return;
    };
    let res = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path())
        .and_then(|mut f| writeln!(f, "{line}"));
    if let Err(e) = res {
        log::warn!("K2K connection log write failed: {}", e);
    }
}

/// JSON array of the most recent entries, newest first.
pub fn recent_json() -> String {
    let text = std::fs::read_to_string(path()).unwrap_or_default();
    let items: Vec<&str> = text
        .lines()
        .filter(|l| !l.trim().is_empty())
        .rev()
        .take(MAX_LINES_RETURNED)
        .collect();
    format!("[{}]", items.join(","))
}
