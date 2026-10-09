#ifndef INA228_H
#define INA228_H
#include <stdint.h>
/* Register addresses and units: TI INA228 SLYS021A, sections 7.6 and 8.1.2. */
#define INA228_CONFIG 0x00u
#define INA228_ADC_CONFIG 0x01u
#define INA228_SHUNT_CAL 0x02u
#define INA228_VSHUNT 0x04u
#define INA228_VBUS 0x05u
#define INA228_DIETEMP 0x06u
#define INA228_CURRENT 0x07u
#define INA228_DIAG_ALRT 0x0bu
#define INA228_MANUFACTURER_ID 0x3eu
#define INA228_DEVICE_ID 0x3fu
typedef enum {
    INA228_OK=0, INA228_BAD_CONFIG, INA228_IO_ERROR, INA228_WRONG_DEVICE,
    INA228_VERIFY_ERROR, INA228_CONVERSION_TIMEOUT, INA228_MATH_OVERFLOW,
    INA228_MEMORY_ERROR, INA228_RANGE_ERROR
} ina228_status_t;
typedef struct {
    void *context;
    int (*read)(void *context, uint8_t address, uint8_t reg, uint8_t bytes, uint32_t *value);
    int (*write16)(void *context, uint8_t address, uint8_t reg, uint16_t value);
} ina228_io_t;
typedef struct {
    uint8_t address;           /* 7-bit I2C address, 0x40..0x4f. */
    uint8_t adc_range;         /* 0 or 1; determines shunt range/calibration. */
    uint32_t shunt_uohm;       /* Measured/board-specified resistance, micro-ohm. */
    uint32_t current_lsb_na;   /* Software scaling of one CURRENT count, nanoamp. */
} ina228_config_t;
typedef struct {
    ina228_io_t io;
    ina228_config_t config;
    uint16_t calibration;
    uint8_t initialized;
} ina228_t;
typedef struct {
    int32_t voltage_mv;
    int32_t current_ma;
    int32_t shunt_uv;
    int32_t die_temperature_deci_c; /* Chip die only, not battery temperature. */
} ina228_sample_t;
/* No sensor traffic when config invalid. Sets initialized only after ID/readback pass. */
ina228_status_t ina228_init(ina228_t *device, const ina228_io_t *io, const ina228_config_t *config);
/* Triggers one coherent conversion (shutdown afterward), bounded status polls.
 * Output is untouched on any error. No IRQ, float, energy/charge accumulator. */
ina228_status_t ina228_read_sample(ina228_t *device, ina228_sample_t *output);
#endif
