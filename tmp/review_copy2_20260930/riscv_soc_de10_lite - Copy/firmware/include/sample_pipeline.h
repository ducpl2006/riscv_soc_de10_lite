#ifndef SAMPLE_PIPELINE_H
#define SAMPLE_PIPELINE_H
#include <stdint.h>
#define SAMPLE_WINDOW 20u
#define SAMPLE_FEATURES 80u
#define SAMPLE_HAS_VI 1u
#define SAMPLE_HAS_CELL_TEMP 2u
/* Đơn vị của từng đầu vào được ghi ngay trong tên. Die temperature của INA228
 * không tự động trở thành cell_temperature_deci_c của mô hình CALCE. */
typedef struct {
    int32_t voltage_mv;
    int32_t current_ma;
    int32_t cell_temperature_deci_c;
    int32_t delta_ms;
    uint32_t valid; /* SAMPLE_HAS_*: chỉ đặt bit khi nguồn dữ liệu hợp lệ. */
} battery_sample_t;
typedef struct {
    battery_sample_t samples[SAMPLE_WINDOW];
    uint32_t next;  /* Vị trí ghi mẫu mới; khi đầy cũng là mẫu cũ nhất. */
    uint32_t count; /* 0..20; không suy luận khi chưa đủ 20 mẫu liên tiếp. */
} sample_buffer_t;
void sample_buffer_reset(sample_buffer_t *buffer);
/* Trả 0 và xóa cửa sổ khi mẫu lỗi/gap; trả 1 khi nhận mẫu. */
int sample_buffer_push(sample_buffer_t *buffer, const battery_sample_t *sample);
/* Output: 80 int8 theo [mẫu cũ nhất..mới nhất][V,I,T,dt].
 * Trả 0 nếu thiếu mẫu hoặc nhiệt độ pin; không ghi output khi từ chối. */
int sample_build_features(const sample_buffer_t *buffer, int8_t output[SAMPLE_FEATURES]);
#endif
