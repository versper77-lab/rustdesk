//! K2K: the controller asks a Windows host for its shareable windows and picks
//! one to share. Replies arrive on the session I/O loop and are kept here,
//! per peer, for the UI to read.

use std::{collections::HashMap, sync::Mutex};

static LAST: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

pub fn store(peer_id: &str, json: String) {
    let mut lock = LAST.lock().unwrap();
    lock.get_or_insert_with(HashMap::new)
        .insert(peer_id.to_owned(), json);
}

/// Takes the latest reply for `peer_id`, or "" when none has arrived yet.
pub fn take(peer_id: &str) -> String {
    let mut lock = LAST.lock().unwrap();
    lock.as_mut()
        .and_then(|m| m.remove(peer_id))
        .unwrap_or_default()
}
