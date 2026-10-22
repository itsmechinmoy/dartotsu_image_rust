use fast_image_resize::images::Image;
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
use image::{DynamicImage, ImageDecoder, ImageReader};
use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::{fs, ptr};

const MAX_SIDE: u32 = 20_000;
const MAX_PIXELS: u64 = 120_000_000;

pub const OK: i32 = 0;
pub const UNCHANGED: i32 = 1;
pub const ERR_ARGS: i32 = -1;
pub const ERR_READ: i32 = -2;
pub const ERR_DECODE: i32 = -3;
pub const ERR_SIZE: i32 = -4;
pub const ERR_RESIZE: i32 = -5;
pub const ERR_PANIC: i32 = -9;

struct Scaled {
    pixels: Vec<u8>,
    width: u32,
    height: u32,
}

fn fitted(src_w: u32, src_h: u32, max_w: u32, max_h: u32) -> Option<(u32, u32)> {
    let scale = match (max_w, max_h) {
        (0, 0) => return None,
        (w, 0) => w as f64 / src_w as f64,
        (0, h) => h as f64 / src_h as f64,
        (w, h) => (w as f64 / src_w as f64).min(h as f64 / src_h as f64),
    };
    if scale >= 1.0 {
        return None;
    }
    let w = ((src_w as f64 * scale).round() as u32).max(1);
    let h = ((src_h as f64 * scale).round() as u32).max(1);
    Some((w, h))
}

fn algorithm(id: u32) -> ResizeAlg {
    match id {
        0 => ResizeAlg::Nearest,
        1 => ResizeAlg::Convolution(FilterType::Bilinear),
        2 => ResizeAlg::Convolution(FilterType::CatmullRom),
        _ => ResizeAlg::Convolution(FilterType::Lanczos3),
    }
}

fn scale_bytes(bytes: &[u8], max_w: u32, max_h: u32, alg: u32) -> Result<Option<Scaled>, i32> {
    let reader = ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| ERR_DECODE)?;
    let decoder = reader.into_decoder().map_err(|_| ERR_DECODE)?;
    let (src_w, src_h) = decoder.dimensions();
    if src_w == 0 || src_h == 0 || src_w > MAX_SIDE || src_h > MAX_SIDE {
        return Err(ERR_SIZE);
    }
    if src_w as u64 * src_h as u64 > MAX_PIXELS {
        return Err(ERR_SIZE);
    }
    let Some((dst_w, dst_h)) = fitted(src_w, src_h, max_w, max_h) else {
        return Ok(None);
    };

    let decoded = DynamicImage::from_decoder(decoder).map_err(|_| ERR_DECODE)?;
    let has_alpha = decoded.color().has_alpha();
    let src = Image::from_vec_u8(src_w, src_h, decoded.into_rgba8().into_raw(), PixelType::U8x4)
        .map_err(|_| ERR_DECODE)?;
    let mut dst = Image::new(dst_w, dst_h, PixelType::U8x4);

    let options = ResizeOptions::new()
        .resize_alg(algorithm(alg))
        .use_alpha(has_alpha);
    Resizer::new()
        .resize(&src, &mut dst, &options)
        .map_err(|_| ERR_RESIZE)?;

    Ok(Some(Scaled {
        pixels: dst.into_vec(),
        width: dst_w,
        height: dst_h,
    }))
}

/// Scales the image file at `path` down to fit inside `max_width` x `max_height`
/// (0 = unbounded on that axis) and writes RGBA8 pixels to `out_ptr`.
///
/// Returns `UNCHANGED` (1) without decoding when the image already fits, `OK` (0)
/// on success, a negative error code otherwise. Free the buffer with
/// `dartotsu_image_free`.
#[no_mangle]
pub extern "C" fn dartotsu_image_scale_file(
    path: *const c_char,
    max_width: u32,
    max_height: u32,
    algorithm: u32,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    if path.is_null()
        || out_ptr.is_null()
        || out_len.is_null()
        || out_width.is_null()
        || out_height.is_null()
    {
        return ERR_ARGS;
    }
    let result = catch_unwind(AssertUnwindSafe(|| {
        let path = unsafe { CStr::from_ptr(path) }
            .to_str()
            .map_err(|_| ERR_ARGS)?;
        let bytes = fs::read(path).map_err(|_| ERR_READ)?;
        scale_bytes(&bytes, max_width, max_height, algorithm)
    }));
    match result {
        Err(_) => ERR_PANIC,
        Ok(Err(code)) => code,
        Ok(Ok(None)) => UNCHANGED,
        Ok(Ok(Some(scaled))) => {
            let boxed = scaled.pixels.into_boxed_slice();
            let len = boxed.len();
            unsafe {
                *out_ptr = Box::into_raw(boxed) as *mut u8;
                *out_len = len;
                *out_width = scaled.width;
                *out_height = scaled.height;
            }
            OK
        }
    }
}

/// Frees a buffer returned by `dartotsu_image_scale_file`.
#[no_mangle]
pub extern "C" fn dartotsu_image_free(buffer: *mut u8, len: usize) {
    if buffer.is_null() || len == 0 {
        return;
    }
    unsafe {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(buffer, len)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageFormat, Rgb, RgbImage};
    use std::io::Cursor;

    fn jpeg(w: u32, h: u32) -> Vec<u8> {
        let img = RgbImage::from_fn(w, h, |x, y| Rgb([(x % 256) as u8, (y % 256) as u8, 128]));
        let mut out = Vec::new();
        DynamicImage::ImageRgb8(img)
            .write_to(&mut Cursor::new(&mut out), ImageFormat::Jpeg)
            .unwrap();
        out
    }

    #[test]
    fn fits_width_keeping_aspect() {
        let s = scale_bytes(&jpeg(800, 1200), 400, 0, 3).unwrap().unwrap();
        assert_eq!((s.width, s.height), (400, 600));
        assert_eq!(s.pixels.len(), 400 * 600 * 4);
    }

    #[test]
    fn fits_inside_box() {
        let s = scale_bytes(&jpeg(1000, 500), 500, 100, 2).unwrap().unwrap();
        assert_eq!((s.width, s.height), (200, 100));
    }

    #[test]
    fn never_upscales() {
        assert!(scale_bytes(&jpeg(300, 300), 600, 0, 3).unwrap().is_none());
        assert!(scale_bytes(&jpeg(300, 300), 300, 300, 3).unwrap().is_none());
        assert!(scale_bytes(&jpeg(300, 300), 0, 0, 3).unwrap().is_none());
    }

    #[test]
    fn every_algorithm_works() {
        let data = jpeg(200, 200);
        for alg in 0..4 {
            let s = scale_bytes(&data, 100, 0, alg).unwrap().unwrap();
            assert_eq!((s.width, s.height), (100, 100));
        }
    }

    #[test]
    fn garbage_is_an_error_not_a_panic() {
        assert!(scale_bytes(&[1, 2, 3, 4, 5], 100, 0, 3).is_err());
        let mut truncated = jpeg(400, 400);
        truncated.truncate(truncated.len() / 3);
        let _ = scale_bytes(&truncated, 100, 0, 3);
    }

    #[test]
    fn tiny_image_is_unchanged() {
        let mut out = Vec::new();
        let img = image::GrayImage::new(1, 1);
        DynamicImage::ImageLuma8(img)
            .write_to(&mut Cursor::new(&mut out), ImageFormat::Png)
            .unwrap();
        assert!(scale_bytes(&out, 1, 0, 3).unwrap().is_none());
    }

    #[test]
    fn ffi_round_trip() {
        let dir = std::env::temp_dir().join("dartotsu_image_rust_test.jpg");
        fs::write(&dir, jpeg(640, 480)).unwrap();
        let path = std::ffi::CString::new(dir.to_str().unwrap()).unwrap();
        let (mut p, mut len, mut w, mut h) = (ptr::null_mut(), 0usize, 0u32, 0u32);
        let code = dartotsu_image_scale_file(path.as_ptr(), 320, 0, 3, &mut p, &mut len, &mut w, &mut h);
        assert_eq!(code, OK);
        assert_eq!((w, h, len), (320, 240, 320 * 240 * 4));
        dartotsu_image_free(p, len);
        let code = dartotsu_image_scale_file(path.as_ptr(), 4000, 0, 3, &mut p, &mut len, &mut w, &mut h);
        assert_eq!(code, UNCHANGED);
        let missing = std::ffi::CString::new("/nonexistent/x.jpg").unwrap();
        assert_eq!(
            dartotsu_image_scale_file(missing.as_ptr(), 100, 0, 3, &mut p, &mut len, &mut w, &mut h),
            ERR_READ
        );
        let _ = fs::remove_file(dir);
    }
}
