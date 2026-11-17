// K2K: keep a monitor that was off before an incoming session off, the way
// AnyDesk does. Starting a session (capture, the connection window, ...) makes
// Windows switch the display back on; if it was off right before, switch it off
// again a few seconds later. Remote input still wakes it, as on any Windows PC.
use std::{
    sync::{
        atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering},
        Once,
    },
    time::Duration,
};
use windows::{
    core::GUID,
    Win32::{
        Foundation::{HANDLE, HWND, LPARAM, WPARAM},
        System::Power::{
            PowerSettingRegisterNotification, DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS,
            POWERBROADCAST_SETTING,
        },
        UI::WindowsAndMessaging::{
            PostMessageW, DEVICE_NOTIFY_CALLBACK, HWND_BROADCAST, SC_MONITORPOWER, WM_SYSCOMMAND,
        },
    },
};

// GUID_CONSOLE_DISPLAY_STATE: 0 = off, 1 = on, 2 = dimmed
const GUID_CONSOLE_DISPLAY_STATE: GUID = GUID::from_u128(0x6fe69556_704a_47a0_8f24_c28d936fda47);
const PBT_POWERSETTINGCHANGE: u32 = 0x8013;
const STATE_UNKNOWN: u32 = u32::MAX;

static DISPLAY_STATE: AtomicU32 = AtomicU32::new(STATE_UNKNOWN);
static REMOTE_COUNT: AtomicUsize = AtomicUsize::new(0);
static TURNING_OFF: AtomicBool = AtomicBool::new(false);

unsafe extern "system" fn on_power(
    _context: *const core::ffi::c_void,
    kind: u32,
    setting: *const core::ffi::c_void,
) -> u32 {
    if kind == PBT_POWERSETTINGCHANGE && !setting.is_null() {
        let s = &*(setting as *const POWERBROADCAST_SETTING);
        if s.PowerSetting == GUID_CONSOLE_DISPLAY_STATE && s.DataLength >= 4 {
            let v = std::ptr::read_unaligned(s.Data.as_ptr() as *const u32);
            let prev = DISPLAY_STATE.swap(v, Ordering::SeqCst);
            if prev != v {
                // Pairs with the session log to show which step wakes the display.
                log::info!("K2K display state: {} -> {} (0=off 1=on 2=dim)", prev as i64, v);
            }
        }
    }
    0
}

/// Starts following the display state (once per process).
pub fn start() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| unsafe {
        let params = Box::leak(Box::new(DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS {
            Callback: Some(on_power),
            Context: std::ptr::null_mut(),
        }));
        let mut handle: *mut core::ffi::c_void = std::ptr::null_mut();
        let _ = PowerSettingRegisterNotification(
            &GUID_CONSOLE_DISPLAY_STATE,
            DEVICE_NOTIFY_CALLBACK,
            HANDLE(params as *mut DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS as *mut core::ffi::c_void),
            &mut handle,
        );
    });
}

fn monitor_off() {
    unsafe {
        let _ = PostMessageW(
            Some(HWND_BROADCAST),
            WM_SYSCOMMAND,
            WPARAM(SC_MONITORPOWER as usize),
            LPARAM(2),
        );
    }
}

/// Called whenever the number of remote-control sessions changes. When the
/// first one starts while the display is off, put the display back to sleep
/// once the session has started up.
pub fn on_remote_count(count: usize, enabled: bool) {
    let prev = REMOTE_COUNT.swap(count, Ordering::SeqCst);
    if !enabled || prev != 0 || count == 0 {
        return;
    }
    if DISPLAY_STATE.load(Ordering::SeqCst) != 0 {
        return;
    }
    if TURNING_OFF.swap(true, Ordering::SeqCst) {
        return;
    }
    let _ = std::thread::Builder::new()
        .name("k2k-monitor-off".to_owned())
        .spawn(|| {
            // The display wakes a moment after the session starts; switch it
            // off once, then leave it to the user (remote input wakes it).
            for _ in 0..2 {
                std::thread::sleep(Duration::from_secs(3));
                if REMOTE_COUNT.load(Ordering::SeqCst) == 0 {
                    break;
                }
                if DISPLAY_STATE.load(Ordering::SeqCst) != 0 {
                    log::info!("K2K: display woke at session start, switching it off again");
                    monitor_off();
                    break;
                }
            }
            TURNING_OFF.store(false, Ordering::SeqCst);
        });
}
