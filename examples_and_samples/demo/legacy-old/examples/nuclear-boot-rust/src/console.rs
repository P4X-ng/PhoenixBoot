/*
 * Console module - VGA text mode output with Rust safety
 */

use core::fmt;
use spin::Mutex;
use x86_64::instructions::port::Port;
use lazy_static::lazy_static;

// VGA text mode constants
const BUFFER_HEIGHT: usize = 25;
const BUFFER_WIDTH: usize = 80;
const VGA_BUFFER: usize = 0xb8000;

// Color codes for VGA text mode
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Color {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    Pink = 13,
    Yellow = 14,
    White = 15,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(transparent)]
struct ColorCode(u8);

impl ColorCode {
    const fn new(foreground: Color, background: Color) -> ColorCode {
        ColorCode((background as u8) << 4 | (foreground as u8))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(C)]
struct ScreenChar {
    ascii_character: u8,
    color_code: ColorCode,
}

type Buffer = [[ScreenChar; BUFFER_WIDTH]; BUFFER_HEIGHT];

pub struct Writer {
    column_position: usize,
    color_code: ColorCode,
    buffer: &'static mut Buffer,
}

impl Writer {
    fn new() -> Writer {
        Writer {
            column_position: 0,
            color_code: ColorCode::new(Color::Yellow, Color::Black),
            buffer: unsafe { &mut *(VGA_BUFFER as *mut Buffer) },
        }
    }

    pub fn write_byte(&mut self, byte: u8) {
        match byte {
            b'\n' => self.new_line(),
            byte => {
                if self.column_position >= BUFFER_WIDTH {
                    self.new_line();
                }

                let row = BUFFER_HEIGHT - 1;
                let col = self.column_position;

                let color_code = self.color_code;
                self.buffer[row][col] = ScreenChar {
                    ascii_character: byte,
                    color_code,
                };
                self.column_position += 1;
            }
        }
        self.update_cursor();
    }

    pub fn write_string(&mut self, s: &str) {
        for byte in s.bytes() {
            match byte {
                // printable ASCII byte or newline
                0x20..=0x7e | b'\n' => self.write_byte(byte),
                // not part of printable ASCII range
                _ => self.write_byte(0xfe),
            }
        }
    }

    fn new_line(&mut self) {
        for row in 1..BUFFER_HEIGHT {
            for col in 0..BUFFER_WIDTH {
                let character = self.buffer[row][col];
                self.buffer[row - 1][col] = character;
            }
        }
        self.clear_row(BUFFER_HEIGHT - 1);
        self.column_position = 0;
    }

    fn clear_row(&mut self, row: usize) {
        let blank = ScreenChar {
            ascii_character: b' ',
            color_code: self.color_code,
        };
        for col in 0..BUFFER_WIDTH {
            self.buffer[row][col] = blank;
        }
    }

    fn update_cursor(&mut self) {
        let pos = (BUFFER_HEIGHT - 1) * BUFFER_WIDTH + self.column_position;
        
        unsafe {
            let mut port1: Port<u8> = Port::new(0x3D4);
            let mut port2: Port<u8> = Port::new(0x3D5);
            
            port1.write(0x0F);
            port2.write((pos & 0xFF) as u8);
            port1.write(0x0E);
            port2.write(((pos >> 8) & 0xFF) as u8);
        }
    }

    pub fn set_color(&mut self, foreground: Color, background: Color) {
        self.color_code = ColorCode::new(foreground, background);
    }
}

impl fmt::Write for Writer {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.write_string(s);
        Ok(())
    }
}

// Global writer instance
lazy_static! {
    pub static ref WRITER: Mutex<Writer> = Mutex::new(Writer::new());
}

pub fn init() {
    // Clear screen and show Nuclear Boot banner
    let mut writer = WRITER.lock();
    writer.set_color(Color::Yellow, Color::Black);
    
    // Clear screen
    for row in 0..BUFFER_HEIGHT {
        writer.clear_row(row);
    }
    writer.column_position = 0;
}

// Print macros
#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => ($crate::console::_print(format_args!($($arg)*)));
}

#[macro_export]
macro_rules! println {
    () => (print!("\n"));
    ($($arg:tt)*) => (print!("{};\n", format_args!($($arg)*)));
}

#[doc(hidden)]
pub fn _print(args: fmt::Arguments) {
    use core::fmt::Write;
    use x86_64::instructions::interrupts;
    
    interrupts::without_interrupts(|| {
        WRITER.lock().write_fmt(args).unwrap();
    });
}

// Color printing functions
pub fn print_success(message: &str) {
    use x86_64::instructions::interrupts;
    
    interrupts::without_interrupts(|| {
        let mut writer = WRITER.lock();
        writer.set_color(Color::LightGreen, Color::Black);
        let _ = fmt::write(&mut *writer, format_args!("{}\n", message));
        writer.set_color(Color::Yellow, Color::Black);
    });
}

pub fn print_error(message: &str) {
    use x86_64::instructions::interrupts;
    
    interrupts::without_interrupts(|| {
        let mut writer = WRITER.lock();
        writer.set_color(Color::LightRed, Color::Black);
        let _ = fmt::write(&mut *writer, format_args!("{}\n", message));
        writer.set_color(Color::Yellow, Color::Black);
    });
}

pub fn print_info(message: &str) {
    use x86_64::instructions::interrupts;
    
    interrupts::without_interrupts(|| {
        let mut writer = WRITER.lock();
        writer.set_color(Color::LightCyan, Color::Black);
        let _ = fmt::write(&mut *writer, format_args!("{}\n", message));
        writer.set_color(Color::Yellow, Color::Black);
    });
}
