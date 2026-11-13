//! K2K app mode: share one program window instead of the whole desktop.
//!
//! Enabled when the host option `k2k-app-target` holds an executable name
//! (e.g. `notepad.exe`). While enabled, the peer sees a single "display" that
//! is exactly that window, input outside it is dropped, system shortcuts are
//! blocked, and non-desktop sessions (file transfer, terminal, port forward,
//! camera) and the clipboard are refused. If the window cannot be found the
//! peer gets a black placeholder, never the desktop.

use hbb_common::config::Config;

pub const OPTION_APP_TARGET: &str = "k2k-app-target";

pub fn target() -> Option<String> {
    let v = Config::get_option(OPTION_APP_TARGET);
    let v = v.trim();
    if v.is_empty() {
        None
    } else {
        Some(v.to_lowercase())
    }
}

pub fn is_active() -> bool {
    cfg!(windows) && target().is_some()
}

#[cfg(windows)]
pub use imp::*;

#[cfg(windows)]
mod imp {
    use super::super::video_service::CapturerInfo;
    use crate::{
        input::{
            MOUSE_TYPE_DOWN, MOUSE_TYPE_MASK, MOUSE_TYPE_MOVE_RELATIVE, MOUSE_TYPE_TRACKPAD,
            MOUSE_TYPE_WHEEL,
        },
        platform::k2k_window::{self as kw, WindowCapture},
        privacy_mode::INVALID_PRIVACY_MODE_CONN_ID,
    };
    use base::message_proto::{key_event, ControlKey, DisplayInfo, KeyEvent, MouseEvent};
    use hbb_common::{log, protobuf::EnumOrUnknown, ResultType};
    #[cfg(feature = "vram")]
    use scrap::AdapterDevice;
    use scrap::{Frame, PixelBuffer, TraitCapturer};
    use serde_derive::Serialize;
    use std::{
        io,
        sync::Mutex,
        time::{Duration, Instant},
    };
    use windows::Win32::Foundation::HWND;

    const PLACEHOLDER: (i32, i32, usize, usize) = (0, 0, 640, 360);
    const DISPLAY_NAME: &str = "K2K App";

    static CACHED: Mutex<Option<(String, isize)>> = Mutex::new(None);

    fn target_hwnd() -> Option<HWND> {
        let target = super::target()?;
        {
            let lock = CACHED.lock().unwrap();
            if let Some((t, raw)) = lock.as_ref() {
                let hwnd = kw::to_hwnd(*raw);
                if *t == target
                    && kw::is_window(hwnd)
                    && kw::exe_of(hwnd).map(|e| e.eq_ignore_ascii_case(&target)) == Some(true)
                {
                    return Some(hwnd);
                }
            }
        }
        let hwnd = kw::find_by_exe(&target)?;
        *CACHED.lock().unwrap() = Some((target, hwnd.0 as isize));
        Some(hwnd)
    }

    fn current() -> (Option<HWND>, (i32, i32, usize, usize)) {
        if let Some(hwnd) = target_hwnd() {
            if let Some(b) = kw::bounds(hwnd) {
                return (Some(hwnd), b);
            }
        }
        (None, PLACEHOLDER)
    }

    /// Replaces the advertised display list with the shared window.
    pub fn override_displays(displays: Vec<DisplayInfo>) -> Vec<DisplayInfo> {
        if !super::is_active() {
            return displays;
        }
        let (_, (x, y, w, h)) = current();
        let mut d = displays.into_iter().next().unwrap_or_default();
        d.x = x;
        d.y = y;
        d.width = w as _;
        d.height = h as _;
        d.name = DISPLAY_NAME.to_owned();
        d.online = true;
        d.cursor_embedded = false;
        d.scale = 1.0;
        d.original_resolution.clear();
        vec![d]
    }

    pub fn get_capturer() -> ResultType<CapturerInfo> {
        let (hwnd, (x, y, w, h)) = current();
        let capture = match hwnd {
            Some(hwnd) => match WindowCapture::new(hwnd) {
                Ok(c) => Some(c),
                Err(e) => {
                    log::error!("K2K app mode: window capture failed: {}", e);
                    None
                }
            },
            None => {
                log::info!("K2K app mode: target window not found, sending placeholder");
                None
            }
        };
        Ok(CapturerInfo {
            origin: (x, y),
            width: w,
            height: h,
            ndisplay: 1,
            current: 0,
            privacy_mode_id: INVALID_PRIVACY_MODE_CONN_ID,
            _capturer_privacy_mode_id: INVALID_PRIVACY_MODE_CONN_ID,
            capturer: Box::new(AppWindowCapturer {
                capture,
                out: vec![0u8; w * h * 4],
                width: w,
                height: h,
                placeholder_sent: false,
                last_check: Instant::now(),
            }),
        })
    }

    struct AppWindowCapturer {
        capture: Option<WindowCapture>,
        out: Vec<u8>,
        width: usize,
        height: usize,
        placeholder_sent: bool,
        last_check: Instant,
    }

    impl AppWindowCapturer {
        fn bounds_changed(&self) -> bool {
            let (_, (_, _, w, h)) = current();
            w != self.width || h != self.height
        }
    }

    impl TraitCapturer for AppWindowCapturer {
        fn frame<'a>(&'a mut self, timeout: Duration) -> io::Result<Frame<'a>> {
            if self.last_check.elapsed() > Duration::from_millis(500) {
                self.last_check = Instant::now();
                let found = target_hwnd().is_some();
                if found != self.capture.is_some() || self.bounds_changed() {
                    return Err(io::Error::new(
                        io::ErrorKind::Other,
                        "K2K app window changed",
                    ));
                }
            }
            let Some(capture) = self.capture.as_mut() else {
                if !self.placeholder_sent {
                    self.placeholder_sent = true;
                    self.out.fill(0);
                    return Ok(Frame::PixelBuffer(PixelBuffer::with_BGRA(
                        &self.out,
                        self.width,
                        self.height,
                    )));
                }
                std::thread::sleep(timeout.min(Duration::from_millis(100)));
                return Err(io::ErrorKind::WouldBlock.into());
            };
            let deadline = Instant::now() + timeout;
            loop {
                match capture.grab(&mut self.out, self.width, self.height) {
                    Ok(true) => break,
                    Ok(false) => {}
                    Err(e) => {
                        return Err(io::Error::new(io::ErrorKind::Other, e.to_string()));
                    }
                }
                if Instant::now() >= deadline {
                    return Err(io::ErrorKind::WouldBlock.into());
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            Ok(Frame::PixelBuffer(PixelBuffer::with_BGRA(
                &self.out,
                self.width,
                self.height,
            )))
        }

        fn is_gdi(&self) -> bool {
            false
        }

        fn set_gdi(&mut self) -> bool {
            false
        }

        #[cfg(feature = "vram")]
        fn device(&self) -> AdapterDevice {
            AdapterDevice::default()
        }

        #[cfg(feature = "vram")]
        fn set_output_texture(&mut self, _texture: bool) {}
    }

    fn inside(b: (i32, i32, usize, usize), x: i32, y: i32) -> bool {
        x >= b.0 && y >= b.1 && x < b.0 + b.2 as i32 && y < b.1 + b.3 as i32
    }

    /// Whether a mouse event may be injected. Focuses the window on button down.
    pub fn allow_mouse(evt: &MouseEvent) -> bool {
        if !super::is_active() {
            return true;
        }
        let evt_type = evt.mask & MOUSE_TYPE_MASK;
        if evt_type == MOUSE_TYPE_MOVE_RELATIVE || evt_type == MOUSE_TYPE_TRACKPAD {
            return false;
        }
        let (Some(hwnd), b) = current() else {
            return false;
        };
        if evt_type == MOUSE_TYPE_WHEEL {
            return kw::cursor_pos().map(|(x, y)| inside(b, x, y)) == Some(true)
                && kw::foreground_is(hwnd);
        }
        if !inside(b, evt.x, evt.y) {
            return false;
        }
        if evt_type == MOUSE_TYPE_DOWN {
            kw::focus(hwnd);
            return kw::foreground_is(hwnd);
        }
        true
    }

    fn is(key: &EnumOrUnknown<ControlKey>, ck: ControlKey) -> bool {
        key.value() == ck.value()
    }

    /// Whether a key event may be injected. Blocks system shortcuts and keys
    /// that would land outside the shared program.
    pub fn allow_key(evt: &KeyEvent) -> bool {
        if !super::is_active() {
            return true;
        }
        let has = |ck: ControlKey| evt.modifiers.iter().any(|m| is(m, ck));
        if has(ControlKey::Meta) || has(ControlKey::RWin) {
            return false;
        }
        let alt = has(ControlKey::Alt) || has(ControlKey::RAlt);
        let ctrl = has(ControlKey::Control) || has(ControlKey::RControl);
        match &evt.union {
            Some(key_event::Union::ControlKey(ck)) => {
                if is(ck, ControlKey::Meta)
                    || is(ck, ControlKey::RWin)
                    || is(ck, ControlKey::CtrlAltDel)
                    || is(ck, ControlKey::LockScreen)
                {
                    return false;
                }
                if (is(ck, ControlKey::Tab) || is(ck, ControlKey::Escape)) && alt {
                    return false;
                }
                if is(ck, ControlKey::Escape) && ctrl {
                    return false;
                }
            }
            Some(key_event::Union::Chr(c)) => {
                // Windows scan codes of the left/right Windows keys in map mode.
                if matches!(*c, 0xE05B | 0xE05C) {
                    return false;
                }
            }
            _ => {}
        }
        let Some(hwnd) = target_hwnd() else {
            return false;
        };
        if evt.down || evt.press {
            if !kw::foreground_is(hwnd) {
                kw::focus(hwnd);
            }
            return kw::foreground_is(hwnd);
        }
        true
    }

    #[derive(Serialize)]
    struct WindowItem {
        exe: String,
        title: String,
    }

    /// JSON list of shareable windows for the host UI: `[{"exe": .., "title": ..}]`.
    pub fn list_windows_json() -> String {
        let items: Vec<WindowItem> = kw::list_windows()
            .into_iter()
            .map(|w| WindowItem {
                exe: w.exe,
                title: w.title,
            })
            .collect();
        serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_owned())
    }
}
