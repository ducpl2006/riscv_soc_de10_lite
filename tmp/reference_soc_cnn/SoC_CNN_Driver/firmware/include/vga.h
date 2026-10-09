#ifndef VGA_H
#define VGA_H

#include <stdint.h>

// =====================================================
// VGA text mode 80x30, font 8x16, 640x480@60Hz
// =====================================================
#define VGA_COLS        80
#define VGA_ROWS        30
#define VGA_CELLS       (VGA_COLS * VGA_ROWS)   // 2400

// =====================================================
// MÀU 4-BIT: bit3 = intensity, bit2 = R, bit1 = G, bit0 = B
// -----------------------------------------------------
// Intensity chỉ làm sáng kênh R/G/B đã bật, KHÔNG tự tạo màu:
// giá trị 0x8 (chỉ intensity) vẫn ra đen -> không có "grey đậm".
// =====================================================
#define VGA_BLACK           0x0
#define VGA_BLUE            0x1
#define VGA_GREEN           0x2
#define VGA_CYAN            0x3
#define VGA_RED             0x4
#define VGA_MAGENTA         0x5
#define VGA_YELLOW          0x6
#define VGA_WHITE           0x7

#define VGA_BRIGHT_BLUE     0x9
#define VGA_BRIGHT_GREEN    0xA
#define VGA_BRIGHT_CYAN     0xB
#define VGA_BRIGHT_RED      0xC
#define VGA_BRIGHT_MAGENTA  0xD
#define VGA_BRIGHT_YELLOW   0xE
#define VGA_BRIGHT_WHITE    0xF

// Gộp fg/bg thành attribute dùng cho vga_set_color / vga_put_char.
#define VGA_COLOR(fg, bg)   ((uint16_t)((((bg) & 0xF) << 12) | (((fg) & 0xF) << 8)))

#define VGA_DEFAULT_COLOR   VGA_COLOR(VGA_WHITE, VGA_BLACK)

// =====================================================
// KHỞI TẠO
// =====================================================
// Xoá màn hình, đặt cursor (0,0), màu mặc định, scroll = 0, buffer = 0.
// PHẢI gọi trước mọi hàm khác: driver giữ state trong biến static mà
// start.S không zero .bss -> trạng thái lúc boot là rác.
void vga_init(void);

// 1 nếu PLL pixel clock đã lock (STATUS bit 0). Ảnh chỉ ổn định khi = 1.
uint32_t vga_pll_locked(void);

// =====================================================
// VẼ TRỰC TIẾP THEO TOẠ ĐỘ (không đụng cursor của terminal)
// -----------------------------------------------------
// col: 0..79, row: 0..29. Ngoài vùng -> bỏ qua.
// `row` là hàng trong TEXT RAM. Nếu đang scroll (row_offset != 0) thì hàng
// hiển thị trên màn hình = (row - row_offset) mod 30.
// =====================================================
void vga_put_char(uint32_t col, uint32_t row, char c, uint16_t color);

// Ghi thẳng cell 16-bit: [15:12] bg, [11:8] fg, [7:0] mã ASCII.
void vga_put_cell(uint32_t col, uint32_t row, uint16_t cell);

// Đổ toàn màn hình bằng 1 ký tự + màu.
void vga_fill(char c, uint16_t color);

// Xoá màn hình (space, màu hiện tại), cursor về (0,0), scroll = 0.
void vga_clear(void);

// Xoá 1 hàng TEXT RAM.
void vga_clear_row(uint32_t row, uint16_t color);

// =====================================================
// TERMINAL: in tại cursor, tự xuống dòng và scroll
// =====================================================
// Màu áp dụng cho các ký tự in SAU lời gọi này.
void vga_set_color(uint16_t color);

// Di chuyển cursor. Cursor nhấp nháy do phần cứng vẽ (~1.5Hz).
void vga_set_cursor(uint32_t col, uint32_t row);

// In 1 ký tự. Hiểu '\n' (xuống dòng + về đầu dòng), '\r' (về đầu dòng),
// '\b' / 0x7F (xoá lùi). Hết dòng -> tự wrap; hết màn hình -> tự scroll.
void vga_putc(char c);

void vga_print(const char *s);
void vga_print_buffer(volatile char *buf, uint32_t len);
void vga_print_hex32(uint32_t v);
void vga_print_dec(uint32_t v);
void vga_print_int(int32_t v);

// =====================================================
// SCROLL / DOUBLE BUFFER (phần cứng)
// =====================================================
// Scroll cứng: dịch cả màn hình lên `n` hàng (0..29), không copy RAM.
// Hàng hiển thị 0 = hàng TEXT RAM `n`. Có hiệu lực ở vsync kế tiếp.
void vga_set_row_offset(uint32_t n);

uint32_t vga_get_row_offset(void);

// CẢNH BÁO: VGA_RAM.v hiện là single-buffer, chân buffer_sel bị bỏ qua.
// Hàm này chỉ set bit trong CTRL, chưa có tác dụng cho tới khi VGA_RAM
// được làm thành double buffer thật.
void vga_set_buffer(uint32_t sel);

#endif // VGA_H
