//! K2K: keeps a host from going to sleep while K2K runs, so it can still be
//! reached remotely (the screen may still turn off). Host option
//! `k2k-keep-awake` = `N` turns it off.

use hbb_common::config::Config;
use std::{sync::Once, time::Duration};
use winapi::um::{winbase::SetThreadExecutionState, winnt::ES_SYSTEM_REQUIRED};

pub const OPTION_KEEP_AWAKE: &str = "k2k-keep-awake";

pub fn start() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let _ = std::thread::Builder::new()
            .name("k2k-keep-awake".to_owned())
            .spawn(|| loop {
                if Config::get_option(OPTION_KEEP_AWAKE) != "N" {
                    // Resets the system idle timer; without ES_CONTINUOUS it
                    // never pins anything, so turning the option off just stops.
                    unsafe {
                        SetThreadExecutionState(ES_SYSTEM_REQUIRED);
                    }
                }
                std::thread::sleep(Duration::from_secs(30));
            });
    });
}
