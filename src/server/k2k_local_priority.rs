//! K2K: the person sitting at the host wins when both sides use the mouse or
//! keyboard at the same time. Remote input is dropped for a short time after
//! any physical local input. Releases are always let through so nothing stays
//! pressed. Disabled with the host option `k2k-local-priority` = `N`.

use crate::input::{MOUSE_TYPE_MASK, MOUSE_TYPE_UP};
use base::message_proto::{KeyEvent, MouseEvent};
use hbb_common::config::Config;

pub const OPTION_LOCAL_PRIORITY: &str = "k2k-local-priority";
const HOLD_MS: u64 = 1_000;

fn enabled() -> bool {
    Config::get_option(OPTION_LOCAL_PRIORITY) != "N"
}

fn local_busy() -> bool {
    if !enabled() {
        return false;
    }
    crate::platform::k2k_local_input::start();
    crate::platform::k2k_local_input::active_within(HOLD_MS)
}

pub fn allow_mouse(evt: &MouseEvent) -> bool {
    evt.mask & MOUSE_TYPE_MASK == MOUSE_TYPE_UP || !local_busy()
}

pub fn allow_key(evt: &KeyEvent) -> bool {
    (!evt.down && !evt.press) || !local_busy()
}
