//! K2K app mode helpers: window lookup and per-window capture (Windows Graphics Capture).
//! Depends only on `windows` and `std` so it can be type-checked standalone
//! (see tools/k2k-wincheck).

use windows::{
    core::{Error, Interface, Result, BOOL, PWSTR},
    Graphics::{
        Capture::{Direct3D11CaptureFramePool, GraphicsCaptureItem, GraphicsCaptureSession},
        DirectX::{Direct3D11::IDirect3DDevice, DirectXPixelFormat},
        SizeInt32,
    },
    Win32::{
        Foundation::{CloseHandle, E_FAIL, HMODULE, HWND, LPARAM, POINT, RECT},
        Graphics::Gdi::{
            CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDC, GetDIBits,
            ReleaseDC, SelectObject, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS,
        },
        Storage::Xps::{PrintWindow, PRINT_WINDOW_FLAGS},
        Graphics::{
            Direct3D::D3D_DRIVER_TYPE_HARDWARE,
            Direct3D11::{
                D3D11CreateDevice, ID3D11Device, ID3D11DeviceContext, ID3D11Texture2D,
                D3D11_CPU_ACCESS_READ, D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_MAPPED_SUBRESOURCE,
                D3D11_MAP_READ, D3D11_SDK_VERSION, D3D11_TEXTURE2D_DESC, D3D11_USAGE_STAGING,
            },
            Dwm::{DwmGetWindowAttribute, DWMWA_EXTENDED_FRAME_BOUNDS},
            Dxgi::IDXGIDevice,
        },
        System::{
            Threading::{
                OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
                PROCESS_QUERY_LIMITED_INFORMATION,
            },
            WinRT::{
                Direct3D11::{CreateDirect3D11DeviceFromDXGIDevice, IDirect3DDxgiInterfaceAccess},
                Graphics::Capture::IGraphicsCaptureItemInterop,
                RoInitialize, RO_INIT_MULTITHREADED,
            },
        },
        UI::WindowsAndMessaging::{
            EnumWindows, GetCursorPos, GetForegroundWindow, GetWindow, GetWindowRect,
            GetWindowTextLengthW,
            GetWindowTextW, GetWindowThreadProcessId, IsIconic, IsWindow, IsWindowVisible,
            SetForegroundWindow, ShowWindow, GW_OWNER, SW_RESTORE,
        },
    },
};

#[derive(Clone, Debug)]
pub struct WindowInfo {
    pub hwnd: isize,
    pub pid: u32,
    pub exe: String,
    pub title: String,
}

pub fn to_hwnd(raw: isize) -> HWND {
    HWND(raw as *mut core::ffi::c_void)
}

/// Visible, unowned top-level windows that have a title.
pub fn list_windows() -> Vec<WindowInfo> {
    unsafe extern "system" fn collect(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let list = &mut *(lparam.0 as *mut Vec<HWND>);
        list.push(hwnd);
        BOOL(1)
    }
    let mut hwnds: Vec<HWND> = Vec::new();
    unsafe {
        let _ = EnumWindows(Some(collect), LPARAM(&mut hwnds as *mut Vec<HWND> as isize));
    }
    hwnds.into_iter().filter_map(window_info).collect()
}

fn window_info(hwnd: HWND) -> Option<WindowInfo> {
    unsafe {
        if !IsWindowVisible(hwnd).as_bool() {
            return None;
        }
        if let Ok(owner) = GetWindow(hwnd, GW_OWNER) {
            if !owner.is_invalid() {
                return None;
            }
        }
        let len = GetWindowTextLengthW(hwnd);
        if len <= 0 {
            return None;
        }
        let mut buf = vec![0u16; len as usize + 1];
        let n = GetWindowTextW(hwnd, &mut buf);
        let title = String::from_utf16_lossy(&buf[..n.max(0) as usize]);
        if title.trim().is_empty() {
            return None;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        let exe = process_exe(pid)?;
        Some(WindowInfo {
            hwnd: hwnd.0 as isize,
            pid,
            exe,
            title,
        })
    }
}

fn process_exe(pid: u32) -> Option<String> {
    unsafe {
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = [0u16; 1024];
        let mut size = buf.len() as u32;
        let res = QueryFullProcessImageNameW(
            handle,
            PROCESS_NAME_WIN32,
            PWSTR(buf.as_mut_ptr()),
            &mut size,
        );
        let _ = CloseHandle(handle);
        res.ok()?;
        let path = String::from_utf16_lossy(&buf[..size as usize]);
        path.rsplit(|c| c == '\\' || c == '/')
            .next()
            .map(|s| s.to_owned())
    }
}

pub fn find_by_exe(exe: &str) -> Option<HWND> {
    list_windows()
        .into_iter()
        .find(|w| w.exe.eq_ignore_ascii_case(exe))
        .map(|w| to_hwnd(w.hwnd))
}

pub fn is_window(hwnd: HWND) -> bool {
    unsafe { IsWindow(Some(hwnd)).as_bool() }
}

pub fn exe_of(hwnd: HWND) -> Option<String> {
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
    process_exe(pid)
}

/// Visible bounds (without the invisible resize border) in physical pixels: (x, y, w, h).
/// Width and height are rounded down to even numbers for the video encoders.
pub fn bounds(hwnd: HWND) -> Option<(i32, i32, usize, usize)> {
    unsafe {
        if IsIconic(hwnd).as_bool() {
            let _ = ShowWindow(hwnd, SW_RESTORE);
        }
        let mut r = RECT::default();
        DwmGetWindowAttribute(
            hwnd,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            &mut r as *mut RECT as *mut core::ffi::c_void,
            std::mem::size_of::<RECT>() as u32,
        )
        .ok()?;
        let w = ((r.right - r.left).max(0) as usize) & !1;
        let h = ((r.bottom - r.top).max(0) as usize) & !1;
        if w < 2 || h < 2 {
            return None;
        }
        Some((r.left, r.top, w, h))
    }
}

pub fn focus(hwnd: HWND) {
    unsafe {
        let _ = SetForegroundWindow(hwnd);
    }
}

/// Whether the foreground window belongs to the same process as `hwnd` (its dialogs count).
pub fn foreground_is(hwnd: HWND) -> bool {
    unsafe {
        let fg = GetForegroundWindow();
        if fg == hwnd {
            return true;
        }
        let (mut a, mut b) = (0u32, 0u32);
        GetWindowThreadProcessId(fg, Some(&mut a));
        GetWindowThreadProcessId(hwnd, Some(&mut b));
        a != 0 && a == b
    }
}

pub fn cursor_pos() -> Option<(i32, i32)> {
    let mut p = POINT::default();
    unsafe { GetCursorPos(&mut p).ok()? };
    Some((p.x, p.y))
}

/// Captures one window's content even when other windows cover it.
pub struct WindowCapture {
    device: ID3D11Device,
    context: ID3D11DeviceContext,
    winrt_device: IDirect3DDevice,
    pool: Direct3D11CaptureFramePool,
    session: GraphicsCaptureSession,
    size: SizeInt32,
    staging: Option<(ID3D11Texture2D, u32, u32)>,
}

impl WindowCapture {
    pub fn new(hwnd: HWND) -> Result<Self> {
        unsafe {
            let _ = RoInitialize(RO_INIT_MULTITHREADED);
            let mut device = None;
            let mut context = None;
            D3D11CreateDevice(
                None,
                D3D_DRIVER_TYPE_HARDWARE,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                Some(&mut context),
            )?;
            let device: ID3D11Device = device.ok_or_else(|| Error::from(E_FAIL))?;
            let context: ID3D11DeviceContext = context.ok_or_else(|| Error::from(E_FAIL))?;
            let dxgi: IDXGIDevice = device.cast()?;
            let winrt_device: IDirect3DDevice =
                CreateDirect3D11DeviceFromDXGIDevice(&dxgi)?.cast()?;
            let interop =
                windows::core::factory::<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()?;
            let item: GraphicsCaptureItem = interop.CreateForWindow(hwnd)?;
            let size = item.Size()?;
            let pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
                &winrt_device,
                DirectXPixelFormat::B8G8R8A8UIntNormalized,
                2,
                size,
            )?;
            let session = pool.CreateCaptureSession(&item)?;
            let _ = session.SetIsCursorCaptureEnabled(false);
            let _ = session.SetIsBorderRequired(false);
            session.StartCapture()?;
            Ok(Self {
                device,
                context,
                winrt_device,
                pool,
                session,
                size,
                staging: None,
            })
        }
    }

    /// Copies the newest frame into `out` (BGRA, `w * 4` bytes per row), cropped or
    /// zero-padded to `w` x `h`. Returns `Ok(false)` when no new frame is ready.
    pub fn grab(&mut self, out: &mut [u8], w: usize, h: usize) -> Result<bool> {
        let frame = match self.pool.TryGetNextFrame() {
            Ok(f) => f,
            Err(_) => return Ok(false),
        };
        let content = frame.ContentSize()?;
        if content.Width != self.size.Width || content.Height != self.size.Height {
            self.size = content;
            let _ = self.pool.Recreate(
                &self.winrt_device,
                DirectXPixelFormat::B8G8R8A8UIntNormalized,
                2,
                content,
            );
        }
        let access: IDirect3DDxgiInterfaceAccess = frame.Surface()?.cast()?;
        let texture: ID3D11Texture2D = unsafe { access.GetInterface()? };
        let mut desc = D3D11_TEXTURE2D_DESC::default();
        unsafe { texture.GetDesc(&mut desc) };
        let staging = self.staging_for(&desc)?;
        let src_w = (content.Width.max(0) as usize).min(desc.Width as usize);
        let src_h = (content.Height.max(0) as usize).min(desc.Height as usize);
        let (cw, ch) = (src_w.min(w), src_h.min(h));
        unsafe {
            self.context.CopyResource(&staging, &texture);
            let mut mapped = D3D11_MAPPED_SUBRESOURCE::default();
            self.context
                .Map(&staging, 0, D3D11_MAP_READ, 0, Some(&mut mapped))?;
            out.fill(0);
            let pitch = mapped.RowPitch as usize;
            let base = mapped.pData as *const u8;
            for y in 0..ch {
                let src = std::slice::from_raw_parts(base.add(y * pitch), cw * 4);
                let dst = y * w * 4;
                out[dst..dst + cw * 4].copy_from_slice(src);
            }
            self.context.Unmap(&staging, 0);
        }
        let _ = frame.Close();
        Ok(true)
    }

    fn staging_for(&mut self, desc: &D3D11_TEXTURE2D_DESC) -> Result<ID3D11Texture2D> {
        if let Some((t, w, h)) = &self.staging {
            if *w == desc.Width && *h == desc.Height {
                return Ok(t.clone());
            }
        }
        let mut d = *desc;
        d.Usage = D3D11_USAGE_STAGING;
        d.BindFlags = 0;
        d.CPUAccessFlags = D3D11_CPU_ACCESS_READ.0 as u32;
        d.MiscFlags = 0;
        d.MipLevels = 1;
        d.ArraySize = 1;
        let mut t = None;
        unsafe { self.device.CreateTexture2D(&d, None, Some(&mut t))? };
        let t: ID3D11Texture2D = t.ok_or_else(|| Error::from(E_FAIL))?;
        self.staging = Some((t.clone(), desc.Width, desc.Height));
        Ok(t)
    }
}

impl Drop for WindowCapture {
    fn drop(&mut self) {
        let _ = self.session.Close();
        let _ = self.pool.Close();
    }
}

/// Fallback window capture through `PrintWindow`. Slower than Windows Graphics
/// Capture but it also works from the K2K service (SYSTEM account), where WGC
/// can fail or never deliver frames.
pub struct GdiCapture {
    hwnd: HWND,
    buf: Vec<u8>,
}

impl GdiCapture {
    pub fn new(hwnd: HWND) -> Self {
        Self { hwnd, buf: Vec::new() }
    }

    /// Same contract as [`WindowCapture::grab`]; always produces a frame.
    pub fn grab(&mut self, out: &mut [u8], w: usize, h: usize) -> Result<bool> {
        unsafe {
            let mut wr = RECT::default();
            GetWindowRect(self.hwnd, &mut wr)?;
            let mut ext = wr;
            let _ = DwmGetWindowAttribute(
                self.hwnd,
                DWMWA_EXTENDED_FRAME_BOUNDS,
                &mut ext as *mut RECT as *mut core::ffi::c_void,
                std::mem::size_of::<RECT>() as u32,
            );
            let ww = (wr.right - wr.left).max(1);
            let wh = (wr.bottom - wr.top).max(1);
            let (ox, oy) = (
                (ext.left - wr.left).clamp(0, ww) as usize,
                (ext.top - wr.top).clamp(0, wh) as usize,
            );
            let screen = GetDC(None);
            let mem = CreateCompatibleDC(Some(screen));
            let bmp = CreateCompatibleBitmap(screen, ww, wh);
            let old = SelectObject(mem, bmp.into());
            // PW_RENDERFULLCONTENT (2): also captures DirectX / browser content.
            let _ = PrintWindow(self.hwnd, mem, PRINT_WINDOW_FLAGS(2));
            let mut bi = BITMAPINFO::default();
            bi.bmiHeader = BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: ww,
                biHeight: -wh,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            };
            let (uw, uh) = (ww as usize, wh as usize);
            self.buf.resize(uw * uh * 4, 0);
            let lines = GetDIBits(
                mem,
                bmp,
                0,
                wh as u32,
                Some(self.buf.as_mut_ptr() as *mut core::ffi::c_void),
                &mut bi,
                DIB_RGB_COLORS,
            );
            SelectObject(mem, old);
            let _ = DeleteObject(bmp.into());
            let _ = DeleteDC(mem);
            ReleaseDC(None, screen);
            if lines == 0 {
                return Err(Error::from(E_FAIL));
            }
            out.fill(0);
            let cw = w.min(uw.saturating_sub(ox));
            let ch = h.min(uh.saturating_sub(oy));
            for y in 0..ch {
                let src = ((oy + y) * uw + ox) * 4;
                let dst = y * w * 4;
                out[dst..dst + cw * 4].copy_from_slice(&self.buf[src..src + cw * 4]);
                // GDI leaves alpha at 0; make the pixels opaque.
                for a in out[dst + 3..dst + cw * 4].iter_mut().step_by(4) {
                    *a = 255;
                }
            }
        }
        Ok(true)
    }
}

/// Window capture that starts with Windows Graphics Capture and switches to
/// `PrintWindow` when WGC cannot be created or delivers no frame in time.
pub enum AnyCapture {
    Wgc {
        cap: WindowCapture,
        hwnd: HWND,
        started: std::time::Instant,
        got_frame: bool,
    },
    Gdi(GdiCapture),
}

impl AnyCapture {
    pub fn new(hwnd: HWND) -> (Self, Option<Error>) {
        match WindowCapture::new(hwnd) {
            Ok(cap) => (
                AnyCapture::Wgc {
                    cap,
                    hwnd,
                    started: std::time::Instant::now(),
                    got_frame: false,
                },
                None,
            ),
            Err(e) => (AnyCapture::Gdi(GdiCapture::new(hwnd)), Some(e)),
        }
    }

    pub fn is_gdi(&self) -> bool {
        matches!(self, AnyCapture::Gdi(_))
    }

    pub fn grab(&mut self, out: &mut [u8], w: usize, h: usize) -> Result<bool> {
        match self {
            AnyCapture::Gdi(g) => g.grab(out, w, h),
            AnyCapture::Wgc {
                cap,
                hwnd,
                started,
                got_frame,
            } => {
                let r = cap.grab(out, w, h);
                match r {
                    Ok(true) => {
                        *got_frame = true;
                        Ok(true)
                    }
                    Ok(false) if *got_frame
                        || started.elapsed() < std::time::Duration::from_millis(1500) =>
                    {
                        Ok(false)
                    }
                    _ => {
                        let hwnd = *hwnd;
                        *self = AnyCapture::Gdi(GdiCapture::new(hwnd));
                        self.grab(out, w, h)
                    }
                }
            }
        }
    }
}
