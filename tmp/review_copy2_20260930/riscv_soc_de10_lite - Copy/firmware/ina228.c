#include "include/ina228.h"
#define ADC_SHUTDOWN 0x0b68u
#define ADC_TRIGGER_ALL 0x7b68u
#define CONFIG_RANGE_BIT 0x0010u
#define DIAG_READY 0x0002u
#define DIAG_MEMORY_OK 0x0001u
#define DIAG_MATH_OVERFLOW 0x0200u
#define CONVERSION_POLL_LIMIT 128u

static int read_reg(ina228_t *d, uint8_t reg, uint8_t bytes, uint32_t *value)
{ return d->io.read(d->io.context,d->config.address,reg,bytes,value); }
static int write_reg(ina228_t *d, uint8_t reg, uint16_t value)
{ return d->io.write16(d->io.context,d->config.address,reg,value); }

ina228_status_t ina228_init(ina228_t *d, const ina228_io_t *io, const ina228_config_t *c)
{
    uint32_t value;
    uint64_t calibration;
    if (!d) return INA228_BAD_CONFIG;
    d->initialized=0;
    if (!io || !io->read || !io->write16 || !c || c->address<0x40 || c->address>0x4f ||
        c->adc_range>1 || !c->shunt_uohm || c->shunt_uohm>1000000u ||
        !c->current_lsb_na || c->current_lsb_na>10000000u) return INA228_BAD_CONFIG;
    /* Integer form of TI calibration equation; dimensions nA and micro-ohm.
     * Limits above bound the intermediate product below UINT64_MAX. */
    calibration = (uint64_t)131072u * c->current_lsb_na * c->shunt_uohm;
    if (c->adc_range) calibration *= 4u;
    calibration /= 10000000000ULL;
    if (!calibration || calibration>32767u) return INA228_BAD_CONFIG;
    d->io=*io; d->config=*c; d->calibration=(uint16_t)calibration;
    if (!read_reg(d,INA228_MANUFACTURER_ID,2,&value)) return INA228_IO_ERROR;
    if (value!=0x5449u) return INA228_WRONG_DEVICE;
    if (!read_reg(d,INA228_DEVICE_ID,2,&value)) return INA228_IO_ERROR;
    if ((value>>4)!=0x228u) return INA228_WRONG_DEVICE; /* Any silicon revision. */
    if (!write_reg(d,INA228_ADC_CONFIG,ADC_SHUTDOWN) ||
        !write_reg(d,INA228_CONFIG,c->adc_range ? CONFIG_RANGE_BIT : 0) ||
        !write_reg(d,INA228_SHUNT_CAL,d->calibration)) return INA228_IO_ERROR;
    if (!read_reg(d,INA228_CONFIG,2,&value)) return INA228_IO_ERROR;
    if (value!=(c->adc_range ? CONFIG_RANGE_BIT : 0)) return INA228_VERIFY_ERROR;
    if (!read_reg(d,INA228_SHUNT_CAL,2,&value)) return INA228_IO_ERROR;
    if (value!=d->calibration) return INA228_VERIFY_ERROR;
    if (!read_reg(d,INA228_ADC_CONFIG,2,&value)) return INA228_IO_ERROR;
    if (value!=ADC_SHUTDOWN) return INA228_VERIFY_ERROR;
    d->initialized=1;
    return INA228_OK;
}

static int32_t signed20(uint32_t wire_value)
{
    uint32_t raw=(wire_value>>4)&0xfffffu;
    /* Avoid implementation-defined conversion of a large unsigned to signed. */
    return (int32_t)raw - ((raw & 0x80000u) ? 1048576 : 0);
}

ina228_status_t ina228_read_sample(ina228_t *d, ina228_sample_t *output)
{
    uint32_t value, polls, bus, current, shunt, temp;
    int32_t temperature;
    ina228_sample_t sample;
    if (!d || !d->initialized || !output) return INA228_BAD_CONFIG;
    /* Detect sensor reset/lost calibration before treating current as valid. */
    if (!read_reg(d,INA228_SHUNT_CAL,2,&value)) return INA228_IO_ERROR;
    if (value!=d->calibration) return INA228_VERIFY_ERROR;
    if (!read_reg(d,INA228_CONFIG,2,&value)) return INA228_IO_ERROR;
    if (value!=(d->config.adc_range ? CONFIG_RANGE_BIT : 0)) return INA228_VERIFY_ERROR;
    if (!write_reg(d,INA228_ADC_CONFIG,ADC_TRIGGER_ALL)) return INA228_IO_ERROR;
    for (polls=0; polls<CONVERSION_POLL_LIMIT; ++polls) {
        if (!read_reg(d,INA228_DIAG_ALRT,2,&value)) return INA228_IO_ERROR;
        if (!(value & DIAG_MEMORY_OK)) return INA228_MEMORY_ERROR;
        if (value & DIAG_MATH_OVERFLOW) return INA228_MATH_OVERFLOW;
        if (value & DIAG_READY) break;
    }
    if (polls==CONVERSION_POLL_LIMIT) return INA228_CONVERSION_TIMEOUT;
    if (!read_reg(d,INA228_VBUS,3,&bus) || !read_reg(d,INA228_CURRENT,3,&current) ||
        !read_reg(d,INA228_VSHUNT,3,&shunt) || !read_reg(d,INA228_DIETEMP,2,&temp)) return INA228_IO_ERROR;
    if ((bus & 0x800000u) || (bus>>4)>435200u) return INA228_RANGE_ERROR;
    sample.voltage_mv=(int32_t)((bus>>4)*25u/128u);
    sample.current_ma=(int32_t)((int64_t)signed20(current)*d->config.current_lsb_na/1000000);
    sample.shunt_uv=signed20(shunt)*5/(d->config.adc_range ? 64 : 16);
    temperature=(int32_t)(temp&0xffffu)-((temp&0x8000u) ? 65536 : 0);
    sample.die_temperature_deci_c=temperature*5/64;
    *output=sample;
    return INA228_OK;
}
