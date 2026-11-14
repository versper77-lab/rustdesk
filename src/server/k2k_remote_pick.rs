//! K2K: lets the controller choose which program window a Windows host
//! shares, by setting the same `k2k-app-target` option the host's own
//! "Share scope" card sets. The host can forbid it with the option
//! `k2k-remote-pick` = `N`. Whatever the host had chosen before is restored
//! when the connection that changed it closes.

use base::message_proto::{Message, Misc};
use hbb_common::{config::Config, log};
use serde_derive::Serialize;
use std::sync::Mutex;

pub const OPTION_REMOTE_PICK: &str = "k2k-remote-pick";

// (connection id that changed the target, the host's own target before it)
static ORIGINAL: Mutex<Option<(i32, String)>> = Mutex::new(None);

fn allowed() -> bool {
    Config::get_option(OPTION_REMOTE_PICK) != "N"
}

#[derive(Serialize)]
struct Reply<'a> {
    allowed: bool,
    current: String,
    windows: serde_json::Value,
    error: &'a str,
}

/// The reply sent to the controller: whether picking is allowed, the current
/// target and the windows that can be shared right now.
pub fn windows_message(error: &str) -> Message {
    let allowed = allowed();
    let windows = if allowed {
        serde_json::from_str(&super::k2k_app_mode::list_windows_json())
            .unwrap_or(serde_json::Value::Array(vec![]))
    } else {
        serde_json::Value::Array(vec![])
    };
    let reply = Reply {
        allowed,
        current: super::k2k_app_mode::target().unwrap_or_default(),
        windows,
        error,
    };
    let mut misc = Misc::new();
    misc.set_k2k_windows(serde_json::to_string(&reply).unwrap_or_default());
    let mut msg = Message::new();
    msg.set_misc(misc);
    msg
}

fn is_listed(exe: &str) -> bool {
    let list = super::k2k_app_mode::list_windows_json();
    serde_json::from_str::<Vec<serde_json::Value>>(&list)
        .unwrap_or_default()
        .iter()
        .any(|w| w["exe"].as_str().map_or(false, |e| e.eq_ignore_ascii_case(exe)))
}

/// Applies the controller's choice. Returns an error code for the reply, or "".
pub fn pick(conn_id: i32, exe: &str) -> &'static str {
    if !allowed() {
        return "not_allowed";
    }
    let exe = exe.trim();
    if !exe.is_empty() && !is_listed(exe) {
        return "not_found";
    }
    {
        let mut lock = ORIGINAL.lock().unwrap();
        if lock.is_none() {
            *lock = Some((
                conn_id,
                Config::get_option(super::k2k_app_mode::OPTION_APP_TARGET),
            ));
        }
    }
    log::info!("K2K share scope set by peer: {:?}", exe);
    Config::set_option(super::k2k_app_mode::OPTION_APP_TARGET.to_owned(), exe.to_owned());
    ""
}

/// Puts back the host's own share scope once the connection that changed it is gone.
pub fn on_connection_closed(conn_id: i32) {
    let original = {
        let mut lock = ORIGINAL.lock().unwrap();
        match lock.as_ref() {
            Some((id, _)) if *id == conn_id => lock.take().map(|(_, v)| v),
            _ => None,
        }
    };
    if let Some(v) = original {
        log::info!("K2K share scope restored: {:?}", v);
        Config::set_option(super::k2k_app_mode::OPTION_APP_TARGET.to_owned(), v);
    }
}
