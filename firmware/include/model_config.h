#ifndef MODEL_CONFIG_H
#define MODEL_CONFIG_H

#include <stdint.h>

/* File sinh tự động bởi ml/train_quantize_export.py. Không sửa bằng tay. */
#define MODEL_ID "BEEDE8E56D64BA8C"
#define MODEL_SEQUENCE_LENGTH 20
#define MODEL_FEATURE_COUNT 4
#define MODEL_INPUT_COUNT 80

enum model_feature_index {
    MODEL_VOLTAGE = 0,
    MODEL_CURRENT = 1,
    MODEL_TEMPERATURE = 2,
    MODEL_DELTA_TIME = 3
};

/* Đơn vị raw: mV, mA, 0.1 độ C, ms. Phép chia nguyên cắt về 0. */
static const int32_t model_feature_center[MODEL_FEATURE_COUNT] = {
    3402, -1000, 225, 10000
};

static const int32_t model_feature_scale[MODEL_FEATURE_COUNT] = {
    5, 24, 2, 1
};

#endif
