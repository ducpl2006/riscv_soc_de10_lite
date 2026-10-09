#include "vga.h"
#include "soc.h"

// TEXT RAM: mỗi cell 16-bit nhưng stride 4 byte (VGA_Register_IF lấy offset[13:2]
// làm chỉ số cell) -> cell N nằm ở VGA_BASE + N*4, vùng 0x0000..0x257F.
#define VGA_TEXT(n)     REG32(VGA_BASE + ((n) << 2))

#define VGA_CTRL        REG32(VGA_BASE + 0x4000)
#define VGA_STAT        REG32(VGA_BASE + 0x4004)

// CTRL: ghi cả word 1 lần, không có byte-enable cho từng field.
#define CTRL_CURSOR_X_SHIFT   0     // [6:0]
#define CTRL_CURSOR_Y_SHIFT   7     // [11:7]
#define CTRL_ROW_OFF_SHIFT    12    // [16:12]
#define CTRL_BUF_SEL_SHIFT    17    // [17]

// STATUS
#define STAT_PLL_LOCKED       (1 << 0)

// Cell: [15:12] bg, [11:8] fg, [7:0] ascii — theo VGA_Text.v (không theo
// comment trong VGA_RAM.v, chỗ đó ghi ngược fg/bg).
#define CELL(color, ch)  ((uint16_t)((color) | ((uint8_t)(ch))))

// ============================================================
// STATE
// ------------------------------------------------------------
// CTRL không đọc-sửa-ghi được: readback trả về active value (chỉ cập nhật ở
// vsync, nên write vừa rồi chưa thấy) và layout field của readback lại KHÁC
// layout lúc ghi. Vì vậy driver giữ shadow trong RAM và luôn ghi cả word.
// Không có initializer nào ở đây được nạp lúc boot (start.S không copy .data
// / không zero .bss) -> vga_init() phải gán hết.
// ============================================================
static uint8_t  g_cursor_x;
static uint8_t  g_cursor_y;     // hàng TEXT RAM, không phải hàng màn hình
static uint8_t  g_row_offset;
static uint8_t  g_buffer_sel;
static uint16_t g_color;

static void vga_ctrl_apply(void)
{
    VGA_CTRL = ((uint32_t)(g_cursor_x   & 0x7F) << CTRL_CURSOR_X_SHIFT)
             | ((uint32_t)(g_cursor_y   & 0x1F) << CTRL_CURSOR_Y_SHIFT)
             | ((uint32_t)(g_row_offset & 0x1F) << CTRL_ROW_OFF_SHIFT)
             | ((uint32_t)(g_buffer_sel & 0x01) << CTRL_BUF_SEL_SHIFT);
}

// ============================================================
// INIT / STATUS
// ============================================================
void vga_init(void)
{
    g_cursor_x   = 0;
    g_cursor_y   = 0;
    g_row_offset = 0;
    g_buffer_sel = 0;
    g_color      = VGA_DEFAULT_COLOR;

    vga_fill(' ', g_color);
    vga_ctrl_apply();
}

uint32_t vga_pll_locked(void)
{
    return (VGA_STAT & STAT_PLL_LOCKED) ? 1u : 0u;
}

// ============================================================
// VẼ THEO TOẠ ĐỘ
// ============================================================
void vga_put_cell(uint32_t col, uint32_t row, uint16_t cell)
{
    if (col >= VGA_COLS || row >= VGA_ROWS)
        return;

    VGA_TEXT(row * VGA_COLS + col) = cell;
}

void vga_put_char(uint32_t col, uint32_t row, char c, uint16_t color)
{
    vga_put_cell(col, row, CELL(color, c));
}

void vga_fill(char c, uint16_t color)
{
    uint16_t cell = CELL(color, c);

    for (uint32_t i = 0; i < VGA_CELLS; i++)
        VGA_TEXT(i) = cell;
}

void vga_clear_row(uint32_t row, uint16_t color)
{
    uint16_t cell = CELL(color, ' ');
    uint32_t base;

    if (row >= VGA_ROWS)
        return;

    base = row * VGA_COLS;

    for (uint32_t i = 0; i < VGA_COLS; i++)
        VGA_TEXT(base + i) = cell;
}

void vga_clear(void)
{
    vga_fill(' ', g_color);

    g_cursor_x   = 0;
    g_cursor_y   = 0;
    g_row_offset = 0;

    vga_ctrl_apply();
}

// ============================================================
// TERMINAL
// ============================================================
void vga_set_color(uint16_t color)
{
    g_color = color;
}

void vga_set_cursor(uint32_t col, uint32_t row)
{
    if (col >= VGA_COLS) col = VGA_COLS - 1;
    if (row >= VGA_ROWS) row = VGA_ROWS - 1;

    g_cursor_x = (uint8_t)col;
    g_cursor_y = (uint8_t)row;

    vga_ctrl_apply();
}

void vga_set_row_offset(uint32_t n)
{
    g_row_offset = (uint8_t)(n % VGA_ROWS);
    vga_ctrl_apply();
}

uint32_t vga_get_row_offset(void)
{
    return g_row_offset;
}

void vga_set_buffer(uint32_t sel)
{
    g_buffer_sel = sel ? 1u : 0u;
    vga_ctrl_apply();
}

// Xuống hàng TEXT RAM kế tiếp. Khi chạm đáy màn hình thì scroll bằng phần cứng:
// tái sử dụng hàng cũ nhất (wrap 30) và tăng row_offset để nó hiện ở đáy,
// thay vì copy 2400 cell qua bus.
//
// Hàng TEXT RAM M hiện ở màn hình tại (M - row_offset) mod 30. Muốn hàng vừa
// wrap tới nằm ở đáy (màn hình 29) -> row_offset = (M + 1) mod 30.
static void vga_newline(void)
{
    g_cursor_x = 0;

    if (g_cursor_y + 1u < VGA_ROWS && g_row_offset == 0)
    {
        // Chưa đầy màn hình lần đầu -> chỉ cần đi xuống.
        g_cursor_y++;
    }
    else
    {
        g_cursor_y   = (uint8_t)((g_cursor_y + 1u) % VGA_ROWS);
        g_row_offset = (uint8_t)((g_cursor_y + 1u) % VGA_ROWS);

        // Hàng vừa lộ ra còn nội dung cũ của 30 dòng trước.
        vga_clear_row(g_cursor_y, g_color);
    }
}

void vga_putc(char c)
{
    if (c == '\n')
    {
        vga_newline();
        vga_ctrl_apply();
        return;
    }

    if (c == '\r')
    {
        g_cursor_x = 0;
        vga_ctrl_apply();
        return;
    }

    if (c == '\b' || c == 127)
    {
        if (g_cursor_x > 0)
        {
            g_cursor_x--;
            vga_put_char(g_cursor_x, g_cursor_y, ' ', g_color);
        }
        vga_ctrl_apply();
        return;
    }

    vga_put_char(g_cursor_x, g_cursor_y, c, g_color);
    g_cursor_x++;

    if (g_cursor_x >= VGA_COLS)
        vga_newline();

    vga_ctrl_apply();
}

void vga_print(const char *s)
{
    while (*s != 0)
    {
        vga_putc(*s);
        s++;
    }
}

void vga_print_buffer(volatile char *buf, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++)
        vga_putc(buf[i]);
}

void vga_print_hex32(uint32_t v)
{
    const char hex[] = "0123456789ABCDEF";

    vga_print("0x");

    for (int i = 7; i >= 0; i--)
        vga_putc(hex[(v >> (i * 4)) & 0xF]);
}

void vga_print_dec(uint32_t v)
{
    char buf[12];
    int  i = 0;

    if (v == 0) { vga_putc('0'); return; }

    while (v)      { buf[i++] = (char)('0' + (v % 10)); v /= 10; }
    while (i)      { vga_putc(buf[--i]); }
}

void vga_print_int(int32_t v)
{
    if (v < 0)
    {
        vga_putc('-');
        v = -v;
    }

    vga_print_dec((uint32_t)v);
}
