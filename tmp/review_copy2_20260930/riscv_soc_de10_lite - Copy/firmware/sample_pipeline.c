#include "include/sample_pipeline.h"
#include "include/model_config.h"
_Static_assert(MODEL_SEQUENCE_LENGTH == SAMPLE_WINDOW, "Model window mismatch");
_Static_assert(MODEL_INPUT_COUNT == SAMPLE_FEATURES && MODEL_FEATURE_COUNT == 4,
               "Feature layout must be reviewed when model changes");

void sample_buffer_reset(sample_buffer_t *buffer)
{
    buffer->next = 0;
    buffer->count = 0;
}

int sample_buffer_push(sample_buffer_t *buffer, const battery_sample_t *sample)
{
    /* 10 s nominal; a gap beyond 15 s invalidates consecutive-sample history. */
    if (!(sample->valid & SAMPLE_HAS_VI) || sample->delta_ms <= 0 || sample->delta_ms > 15000) {
        sample_buffer_reset(buffer);
        return 0;
    }
    buffer->samples[buffer->next] = *sample;
    if (++buffer->next == SAMPLE_WINDOW) buffer->next = 0;
    if (buffer->count < SAMPLE_WINDOW) ++buffer->count;
    return 1;
}

static int8_t quantize(int32_t value, uint32_t feature)
{
    int32_t center = model_feature_center[feature];
    int32_t scale = model_feature_scale[feature];
    /* Clamp before subtraction, avoiding INT32 overflow for malformed input. */
    if (value > center + 127 * scale) return 127;
    if (value < center - 128 * scale) return -128;
    return (int8_t)((value - center) / scale); /* C division truncates toward 0. */
}

int sample_build_features(const sample_buffer_t *buffer, int8_t output[SAMPLE_FEATURES])
{
    uint32_t i, index = buffer->next;
    if (buffer->count != SAMPLE_WINDOW) return 0;
    for (i = 0; i < SAMPLE_WINDOW; ++i)
        if (!(buffer->samples[i].valid & SAMPLE_HAS_CELL_TEMP)) return 0;
    for (i = 0; i < SAMPLE_WINDOW; ++i) {
        const battery_sample_t *s = &buffer->samples[index];
        output[4*i+0] = quantize(s->voltage_mv, MODEL_VOLTAGE);
        output[4*i+1] = quantize(s->current_ma, MODEL_CURRENT);
        output[4*i+2] = quantize(s->cell_temperature_deci_c, MODEL_TEMPERATURE);
        output[4*i+3] = quantize(s->delta_ms, MODEL_DELTA_TIME);
        if (++index == SAMPLE_WINDOW) index = 0;
    }
    return 1;
}
