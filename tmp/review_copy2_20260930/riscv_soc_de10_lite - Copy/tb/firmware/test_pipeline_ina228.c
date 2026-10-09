#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include "sample_pipeline.h"
#include "ina228.h"

typedef struct {
    uint32_t reg[64];
    unsigned reads,writes,fail_io,ready_after,diag_reads,wrong_width;
} mock_t;
static int mock_read(void *context,uint8_t addr,uint8_t reg,uint8_t bytes,uint32_t *value)
{
    mock_t *m=context;
    assert(addr==0x40 && reg<64);
    ++m->reads;
    if(bytes != ((reg==4||reg==5||reg==7) ? 3 : 2)) ++m->wrong_width;
    if(m->fail_io) return 0;
    *value=m->reg[reg];
    if(reg==INA228_DIAG_ALRT && ++m->diag_reads < m->ready_after) *value&=~2u;
    return 1;
}
static int mock_write(void *context,uint8_t addr,uint8_t reg,uint16_t value)
{
    mock_t *m=context;
    assert(addr==0x40 && reg<64);
    ++m->writes;
    if(m->fail_io) return 0;
    m->reg[reg]=value;
    if(reg==INA228_ADC_CONFIG) m->diag_reads=0;
    return 1;
}
static void defaults(mock_t *m)
{
    memset(m,0,sizeof(*m));
    m->reg[INA228_MANUFACTURER_ID]=0x5449;
    m->reg[INA228_DEVICE_ID]=0x228a; /* Revision-independent identity check. */
    m->reg[INA228_DIAG_ALRT]=3;
    m->reg[INA228_VBUS]=0x045000; /* Exactly 3450 mV. */
    m->reg[INA228_CURRENT]=0xe79600; /* -100000 counts -> -1000 mA. */
    m->reg[INA228_VSHUNT]=0xf83000; /* -32000 counts -> -10000 uV at range 0. */
    m->reg[INA228_DIETEMP]=0x0c80; /* +25 C die temperature. */
    m->ready_after=3;
}
static void driver_tests(void)
{
    mock_t m;
    ina228_t d;
    ina228_config_t c={0x40,0,10000,10000};
    ina228_io_t io={&m,mock_read,mock_write};
    ina228_sample_t out,previous;
    defaults(&m);
    assert(ina228_init(&d,&io,&c)==INA228_OK && d.calibration==1310);
    assert(m.reg[0]==0 && m.reg[1]==0x0b68 && m.reg[2]==1310);
    assert(ina228_read_sample(&d,&out)==INA228_OK);
    assert(out.voltage_mv==3450 && out.current_ma==-1000 && out.shunt_uv==-10000 && out.die_temperature_deci_c==250);
    assert(m.diag_reads==3 && m.wrong_width==0);
    m.reg[INA228_CURRENT]=0x186a00; m.reg[INA228_DIETEMP]=0xf380;
    assert(ina228_read_sample(&d,&out)==INA228_OK && out.current_ma==1000 && out.die_temperature_deci_c==-250);
    c.adc_range=1;
    assert(ina228_init(&d,&io,&c)==INA228_OK && d.calibration==5242);
    assert(ina228_read_sample(&d,&out)==INA228_OK && out.shunt_uv==-2500);
    m.reg[INA228_CURRENT]=0x800000;
    assert(ina228_read_sample(&d,&out)==INA228_OK && out.current_ma==-5242);
    previous=out;
    m.ready_after=1000;
    assert(ina228_read_sample(&d,&out)==INA228_CONVERSION_TIMEOUT && m.diag_reads==128);
    assert(memcmp(&out,&previous,sizeof(out))==0);
    m.ready_after=1; m.reg[INA228_DIAG_ALRT]=0x203;
    assert(ina228_read_sample(&d,&out)==INA228_MATH_OVERFLOW);
    m.reg[INA228_DIAG_ALRT]=2;
    assert(ina228_read_sample(&d,&out)==INA228_MEMORY_ERROR);
    m.reg[INA228_DIAG_ALRT]=3; m.reg[INA228_VBUS]=0x800000;
    assert(ina228_read_sample(&d,&out)==INA228_RANGE_ERROR);
    m.reg[INA228_SHUNT_CAL]=0;
    assert(ina228_read_sample(&d,&out)==INA228_VERIFY_ERROR);
    m.fail_io=1;
    assert(ina228_read_sample(&d,&out)==INA228_IO_ERROR);
    assert(memcmp(&out,&previous,sizeof(out))==0);
    defaults(&m); m.reg[INA228_DEVICE_ID]=0x2190;
    assert(ina228_init(&d,&io,&c)==INA228_WRONG_DEVICE && !d.initialized && !m.writes);
    defaults(&m); c.shunt_uohm=0;
    assert(ina228_init(&d,&io,&c)==INA228_BAD_CONFIG && !m.reads && !m.writes);
    c.shunt_uohm=1000000; c.current_lsb_na=10000000;
    assert(ina228_init(&d,&io,&c)==INA228_BAD_CONFIG && !m.reads);
    puts("PASS firmware INA228: widths, identity, calibration/ranges, signed units, bounded conversion, invalid output protection");
}
static void pipeline_tests(void)
{
    sample_buffer_t b;
    battery_sample_t s={3402,-1000,225,10000,3};
    int8_t out[80];
    unsigned n;
    memset(out,0x55,sizeof(out));
    sample_buffer_reset(&b);
    for(n=0;n<19;++n) { s.voltage_mv=3402+5*(int)n; assert(sample_buffer_push(&b,&s)); }
    assert(!sample_build_features(&b,out) && out[0]==0x55);
    s.voltage_mv=3497; assert(sample_buffer_push(&b,&s));
    assert(sample_build_features(&b,out));
    for(n=0;n<20;++n) assert(out[4*n]==(int)n && out[4*n+1]==0 && out[4*n+2]==0 && out[4*n+3]==0);
    s.voltage_mv=3502; assert(sample_buffer_push(&b,&s));
    assert(sample_build_features(&b,out) && out[0]==1 && out[76]==20);
    s.voltage_mv=INT_MAX; s.current_ma=INT_MIN;
    assert(sample_buffer_push(&b,&s) && sample_build_features(&b,out));
    assert(out[76]==127 && out[77]==-128);
    s.valid=1;
    assert(sample_buffer_push(&b,&s));
    memset(out,0x55,sizeof(out));
    assert(!sample_build_features(&b,out) && out[79]==0x55);
    s.valid=0; assert(!sample_buffer_push(&b,&s) && b.count==0);
    s.valid=3; s.delta_ms=15001; assert(!sample_buffer_push(&b,&s));
    s.delta_ms=0; assert(!sample_buffer_push(&b,&s));
    s.delta_ms=10000; s.voltage_mv=3401; s.current_ma=-1023;
    for(n=0;n<20;++n) assert(sample_buffer_push(&b,&s));
    assert(sample_build_features(&b,out) && out[0]==0 && out[1]==0);
    puts("PASS firmware pipeline: warmup, ring order, signed truncation, saturation, gaps, missing temperature");
}
int main(void) { pipeline_tests(); driver_tests(); return 0; }
