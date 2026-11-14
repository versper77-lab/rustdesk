//! K2K detached control: in app mode, the controller can choose to send its
//! input straight to the shared program instead of through the real mouse and
//! keyboard, so the person at the host keeps using their own cursor. The
//! controller switches it per session from the toolbar; the host only acts on
//! it while app mode is active.

use crate::{
    input::{
        MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL, MOUSE_TYPE_DOWN,
        MOUSE_TYPE_MASK, MOUSE_TYPE_MOVE, MOUSE_TYPE_UP, MOUSE_TYPE_WHEEL,
    },
    platform::k2k_post_input::{self as pi, Button},
};
use base::message_proto::{key_event, option_message::BoolOption, ControlKey, KeyEvent, KeyboardMode, MouseEvent};
use hbb_common::protobuf::{Enum, EnumOrUnknown};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicUsize, Ordering};

static DETACHED: AtomicBool = AtomicBool::new(false);
static HELD: AtomicUsize = AtomicUsize::new(0);
static LAST_X: AtomicI32 = AtomicI32::new(0);
static LAST_Y: AtomicI32 = AtomicI32::new(0);

pub fn set_option(o: &EnumOrUnknown<BoolOption>) {
    match o.enum_value() {
        Ok(BoolOption::Yes) => DETACHED.store(true, Ordering::SeqCst),
        Ok(BoolOption::No) => DETACHED.store(false, Ordering::SeqCst),
        _ => {}
    }
    HELD.store(0, Ordering::SeqCst);
}

fn root() -> Option<Option<isize>> {
    if !DETACHED.load(Ordering::Relaxed) || !super::k2k_app_mode::is_active() {
        return None;
    }
    Some(super::k2k_app_mode::window_handle())
}

/// Returns true when the event was handled here and must not be injected.
pub fn handle_mouse(evt: &MouseEvent) -> bool {
    let Some(root) = root() else {
        return false;
    };
    let Some(root) = root else {
        return true;
    };
    let kind = evt.mask & MOUSE_TYPE_MASK;
    let buttons = evt.mask >> 3;
    match kind {
        MOUSE_TYPE_MOVE => {
            LAST_X.store(evt.x, Ordering::Relaxed);
            LAST_Y.store(evt.y, Ordering::Relaxed);
            pi::post_move(root, evt.x, evt.y, HELD.load(Ordering::Relaxed));
        }
        MOUSE_TYPE_DOWN | MOUSE_TYPE_UP => {
            let down = kind == MOUSE_TYPE_DOWN;
            let (button, flag) = match buttons {
                MOUSE_BUTTON_LEFT => (Button::Left, pi::MK_LBUTTON),
                MOUSE_BUTTON_RIGHT => (Button::Right, pi::MK_RBUTTON),
                MOUSE_BUTTON_WHEEL => (Button::Middle, pi::MK_MBUTTON),
                _ => return true,
            };
            let held = if down {
                HELD.fetch_or(flag, Ordering::Relaxed) | flag
            } else {
                HELD.fetch_and(!flag, Ordering::Relaxed) & !flag
            };
            pi::post_button(root, evt.x, evt.y, button, down, held);
        }
        MOUSE_TYPE_WHEEL => {
            if evt.y != 0 {
                pi::post_wheel(
                    root,
                    LAST_X.load(Ordering::Relaxed),
                    LAST_Y.load(Ordering::Relaxed),
                    evt.y.saturating_mul(120),
                    HELD.load(Ordering::Relaxed),
                );
            }
        }
        _ => {}
    }
    true
}

fn vk_of(ck: ControlKey) -> Option<u16> {
    Some(match ck {
        ControlKey::Backspace => 0x08,
        ControlKey::Tab => 0x09,
        ControlKey::Return | ControlKey::NumpadEnter => 0x0D,
        ControlKey::Escape => 0x1B,
        ControlKey::PageUp => 0x21,
        ControlKey::PageDown => 0x22,
        ControlKey::End => 0x23,
        ControlKey::Home => 0x24,
        ControlKey::LeftArrow => 0x25,
        ControlKey::UpArrow => 0x26,
        ControlKey::RightArrow => 0x27,
        ControlKey::DownArrow => 0x28,
        ControlKey::Insert => 0x2D,
        ControlKey::Delete => 0x2E,
        ControlKey::F1 => 0x70,
        ControlKey::F2 => 0x71,
        ControlKey::F3 => 0x72,
        ControlKey::F4 => 0x73,
        ControlKey::F5 => 0x74,
        ControlKey::F6 => 0x75,
        ControlKey::F7 => 0x76,
        ControlKey::F8 => 0x77,
        ControlKey::F9 => 0x78,
        ControlKey::F10 => 0x79,
        ControlKey::F11 => 0x7A,
        ControlKey::F12 => 0x7B,
        _ => return None,
    })
}

fn char_of(ck: ControlKey) -> Option<char> {
    Some(match ck {
        ControlKey::Space => ' ',
        ControlKey::Numpad0 => '0',
        ControlKey::Numpad1 => '1',
        ControlKey::Numpad2 => '2',
        ControlKey::Numpad3 => '3',
        ControlKey::Numpad4 => '4',
        ControlKey::Numpad5 => '5',
        ControlKey::Numpad6 => '6',
        ControlKey::Numpad7 => '7',
        ControlKey::Numpad8 => '8',
        ControlKey::Numpad9 => '9',
        ControlKey::Multiply => '*',
        ControlKey::Add => '+',
        ControlKey::Subtract => '-',
        ControlKey::Decimal => '.',
        ControlKey::Divide => '/',
        _ => return None,
    })
}

fn send_vk(root: isize, vk: u16, scan: u32, evt: &KeyEvent) {
    if evt.press {
        pi::post_vk(root, vk, scan, true);
        pi::post_vk(root, vk, scan, false);
    } else {
        pi::post_vk(root, vk, scan, evt.down);
    }
}

/// Returns true when the event was handled here and must not be injected.
pub fn handle_key(evt: &KeyEvent) -> bool {
    let Some(root) = root() else {
        return false;
    };
    let Some(root) = root else {
        return true;
    };
    let has = |ck: ControlKey| evt.modifiers.iter().any(|m| m.value() == ck.value());
    let shift = has(ControlKey::Shift) || has(ControlKey::RShift);
    let caps = has(ControlKey::CapsLock);
    let chord = has(ControlKey::Control)
        || has(ControlKey::RControl)
        || has(ControlKey::Alt)
        || has(ControlKey::RAlt)
        || has(ControlKey::Meta)
        || has(ControlKey::RWin);
    let typing = evt.down || evt.press;
    match &evt.union {
        Some(key_event::Union::Seq(s)) => {
            if typing {
                s.chars().for_each(|c| pi::post_char(root, c));
            }
        }
        Some(key_event::Union::Unicode(u)) => {
            if let (true, Some(c)) = (typing, char::from_u32(*u)) {
                pi::post_char(root, c);
            }
        }
        Some(key_event::Union::ControlKey(ck)) => {
            let Ok(ck) = ck.enum_value() else {
                return true;
            };
            if let Some(c) = char_of(ck) {
                if typing && !chord {
                    pi::post_char(root, c);
                }
            } else if let Some(vk) = vk_of(ck) {
                send_vk(root, vk, 0, evt);
            }
        }
        Some(key_event::Union::Chr(code)) => {
            if evt.mode.enum_value() == Ok(KeyboardMode::Legacy) {
                if let (true, false, Some(c)) = (typing, chord, char::from_u32(*code)) {
                    if !c.is_control() {
                        pi::post_char(root, c);
                    }
                }
                return true;
            }
            let scan = *code;
            let vk = pi::vk_from_scan(scan);
            if vk == 0 {
                return true;
            }
            if !chord {
                if let Some(c) = pi::char_from_vk(root, vk, scan, shift, caps) {
                    if typing {
                        pi::post_char(root, c);
                    }
                    return true;
                }
            }
            if !matches!(vk, 0x10 | 0x11 | 0x12 | 0x14 | 0x5B | 0x5C | 0xA0..=0xA5) {
                send_vk(root, vk, scan, evt);
            }
        }
        _ => {}
    }
    true
}
