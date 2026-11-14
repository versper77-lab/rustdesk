//! Detects physical (non-injected) mouse and keyboard input on this machine.
//!
//! Low-level hooks see every input event together with a flag telling whether
//! it was injected (e.g. by `SendInput`, which is how remote input arrives).
//! Only events without that flag count as the local user being active.

use std::{
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        OnceLock,
    },
    time::Instant,
};
use windows::Win32::{
    Foundation::{LPARAM, LRESULT, WPARAM},
    UI::WindowsAndMessaging::{
        CallNextHookEx, GetMessageW, SetWindowsHookExW, KBDLLHOOKSTRUCT, MSG, MSLLHOOKSTRUCT,
        WH_KEYBOARD_LL, WH_MOUSE_LL,
    },
};

const MOUSE_INJECTED_MASK: u32 = 0x1 | 0x2;
const KEY_INJECTED_MASK: u32 = 0x10 | 0x2;

static STARTED: AtomicBool = AtomicBool::new(false);
static LAST_LOCAL_MS: AtomicU64 = AtomicU64::new(0);

fn now_ms() -> u64 {
    static BASE: OnceLock<Instant> = OnceLock::new();
    BASE.get_or_init(Instant::now).elapsed().as_millis() as u64 + 1
}

fn mark_local() {
    LAST_LOCAL_MS.store(now_ms(), Ordering::Relaxed);
}

unsafe extern "system" fn mouse_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code >= 0 && lparam.0 != 0 {
        let info = &*(lparam.0 as *const MSLLHOOKSTRUCT);
        if info.flags & MOUSE_INJECTED_MASK == 0 {
            mark_local();
        }
    }
    CallNextHookEx(None, code, wparam, lparam)
}

unsafe extern "system" fn key_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code >= 0 && lparam.0 != 0 {
        let info = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
        if info.flags.0 & KEY_INJECTED_MASK == 0 {
            mark_local();
        }
    }
    CallNextHookEx(None, code, wparam, lparam)
}

/// Starts the hook thread once. If hooks cannot be installed, local input is
/// never reported and remote input keeps working as before.
pub fn start() {
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    let _ = std::thread::Builder::new()
        .name("k2k-local-input".to_owned())
        .spawn(|| unsafe {
            let mouse = SetWindowsHookExW(WH_MOUSE_LL, Some(mouse_proc), None, 0);
            let key = SetWindowsHookExW(WH_KEYBOARD_LL, Some(key_proc), None, 0);
            if mouse.is_err() && key.is_err() {
                return;
            }
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).0 > 0 {}
        });
}

/// Whether the local user used the physical mouse or keyboard within `ms`.
pub fn active_within(ms: u64) -> bool {
    let last = LAST_LOCAL_MS.load(Ordering::Relaxed);
    last != 0 && now_ms().saturating_sub(last) < ms
}
