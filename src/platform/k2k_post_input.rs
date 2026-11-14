//! Sends mouse and keyboard input straight to one window's message queue,
//! without moving the real cursor or changing the foreground window. Works
//! with classic Win32 programs; programs that read raw input or the global
//! keyboard state (many games, some browsers) may ignore it.

use std::sync::atomic::{AtomicIsize, Ordering};
use windows::Win32::{
    Foundation::{HWND, LPARAM, POINT, WPARAM},
    Graphics::Gdi::ScreenToClient,
    UI::{
        Input::KeyboardAndMouse::{GetKeyboardLayout, MapVirtualKeyW, ToUnicodeEx, MAPVK_VSC_TO_VK_EX},
        WindowsAndMessaging::{
            ChildWindowFromPointEx, GetGUIThreadInfo, GetWindowThreadProcessId, PostMessageW,
            CWP_SKIPDISABLED, CWP_SKIPINVISIBLE, CWP_SKIPTRANSPARENT, GUITHREADINFO,
            WM_CHAR, WM_KEYDOWN, WM_KEYUP, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MBUTTONDOWN,
            WM_MBUTTONUP, WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_RBUTTONDOWN, WM_RBUTTONUP,
        },
    },
};

pub const MK_LBUTTON: usize = 0x1;
pub const MK_RBUTTON: usize = 0x2;
pub const MK_MBUTTON: usize = 0x10;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Button {
    Left,
    Right,
    Middle,
}

static LAST_TARGET: AtomicIsize = AtomicIsize::new(0);

fn hwnd(v: isize) -> HWND {
    HWND(v as _)
}

fn lparam_xy(x: i32, y: i32) -> LPARAM {
    LPARAM((((y as u32 & 0xFFFF) << 16) | (x as u32 & 0xFFFF)) as isize)
}

/// Deepest visible, enabled child of `root` under screen point (`sx`, `sy`),
/// with the point in that child's client coordinates.
fn target_at(root: isize, sx: i32, sy: i32) -> (HWND, i32, i32) {
    let mut cur = hwnd(root);
    let mut pt = POINT { x: sx, y: sy };
    unsafe {
        let _ = ScreenToClient(cur, &mut pt);
        for _ in 0..32 {
            let child = ChildWindowFromPointEx(
                cur,
                pt,
                CWP_SKIPINVISIBLE | CWP_SKIPDISABLED | CWP_SKIPTRANSPARENT,
            );
            if child.is_invalid() || child == cur {
                break;
            }
            cur = child;
            pt = POINT { x: sx, y: sy };
            let _ = ScreenToClient(cur, &mut pt);
        }
    }
    (cur, pt.x, pt.y)
}

fn post(target: HWND, msg: u32, wparam: usize, lparam: LPARAM) {
    unsafe {
        let _ = PostMessageW(Some(target), msg, WPARAM(wparam), lparam);
    }
}

pub fn post_move(root: isize, sx: i32, sy: i32, held: usize) {
    let (t, x, y) = target_at(root, sx, sy);
    post(t, WM_MOUSEMOVE, held, lparam_xy(x, y));
}

pub fn post_button(root: isize, sx: i32, sy: i32, button: Button, down: bool, held: usize) {
    let (t, x, y) = target_at(root, sx, sy);
    if down {
        LAST_TARGET.store(t.0 as isize, Ordering::Relaxed);
    }
    let msg = match (button, down) {
        (Button::Left, true) => WM_LBUTTONDOWN,
        (Button::Left, false) => WM_LBUTTONUP,
        (Button::Right, true) => WM_RBUTTONDOWN,
        (Button::Right, false) => WM_RBUTTONUP,
        (Button::Middle, true) => WM_MBUTTONDOWN,
        (Button::Middle, false) => WM_MBUTTONUP,
    };
    post(t, msg, held, lparam_xy(x, y));
}

/// `delta` in WHEEL_DELTA units (120 per notch), positive scrolls up.
pub fn post_wheel(root: isize, sx: i32, sy: i32, delta: i32, held: usize) {
    let (t, _, _) = target_at(root, sx, sy);
    let wparam = ((delta as i16 as u16 as usize) << 16) | (held & 0xFFFF);
    post(t, WM_MOUSEWHEEL, wparam, lparam_xy(sx, sy));
}

/// Window that should receive keyboard input: the program's own focus if it
/// has one, otherwise the last window clicked through this module.
fn key_target(root: isize) -> HWND {
    unsafe {
        let thread = GetWindowThreadProcessId(hwnd(root), None);
        let mut info = GUITHREADINFO {
            cbSize: std::mem::size_of::<GUITHREADINFO>() as u32,
            ..Default::default()
        };
        if thread != 0 && GetGUIThreadInfo(thread, &mut info).is_ok() && !info.hwndFocus.is_invalid() {
            return info.hwndFocus;
        }
    }
    let last = LAST_TARGET.load(Ordering::Relaxed);
    if last != 0 {
        hwnd(last)
    } else {
        hwnd(root)
    }
}

pub fn post_char(root: isize, ch: char) {
    let t = key_target(root);
    let mut buf = [0u16; 2];
    for unit in ch.encode_utf16(&mut buf) {
        post(t, WM_CHAR, *unit as usize, LPARAM(1));
    }
}

pub fn post_vk(root: isize, vk: u16, scan: u32, down: bool) {
    let t = key_target(root);
    let mut lp: u32 = 1 | ((scan & 0xFF) << 16);
    if scan & 0xE000 == 0xE000 {
        lp |= 1 << 24;
    }
    if !down {
        lp |= (1 << 30) | (1 << 31);
    }
    post(t, if down { WM_KEYDOWN } else { WM_KEYUP }, vk as usize, LPARAM(lp as isize));
}

pub fn vk_from_scan(scan: u32) -> u16 {
    let code = if scan & 0xE000 == 0xE000 { 0xE000 | (scan & 0xFF) } else { scan & 0xFF };
    unsafe { MapVirtualKeyW(code, MAPVK_VSC_TO_VK_EX) as u16 }
}

/// Character a key produces in the target program's keyboard layout, using
/// only the given modifier state (not the physical keyboard's).
pub fn char_from_vk(root: isize, vk: u16, scan: u32, shift: bool, caps: bool) -> Option<char> {
    let mut state = [0u8; 256];
    if shift {
        state[0x10] = 0x80;
        state[0xA0] = 0x80;
    }
    if caps {
        state[0x14] = 0x01;
    }
    let mut buf = [0u16; 4];
    let n = unsafe {
        let thread = GetWindowThreadProcessId(hwnd(root), None);
        let hkl = GetKeyboardLayout(thread);
        ToUnicodeEx(vk as u32, scan & 0xFF, &state, &mut buf, 0x4, Some(hkl))
    };
    if n != 1 {
        return None;
    }
    char::from_u32(buf[0] as u32).filter(|c| !c.is_control())
}
