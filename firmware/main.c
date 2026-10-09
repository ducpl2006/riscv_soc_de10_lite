#include <stdint.h>
#include "include/soc_map.h"
#include "include/soc_platform.h"
#include "include/sample_pipeline.h"
#include "include/ina228.h"
#include "include/board_config.h"

static sample_buffer_t window;
static int8_t features[SAMPLE_FEATURES];

/* No battery-temperature sensor has been specified. Keep the model input
 * invalid on hardware; INA228 DIETEMP is diagnostic die temperature only. */
static int read_cell_temperature(int32_t *temperature)
{
    (void)temperature;
    return 0;
}

static int report_result(uint32_t result)
{
    GPIO_LED = (result >> 2) & GPIO_LED_MASK;
    return soc_uart_text("SOC=") && soc_uart_u32(result/10u) && soc_uart_putc('.') &&
           soc_uart_putc((char)('0'+result%10u)) && soc_uart_text("%\n");
}

int main(void)
{
    uint32_t index=0, result, last_time=0;
    ina228_t device;
    ina228_sample_t measured;
    const ina228_io_t io={0,soc_sensor_read,soc_sensor_write16};
    const ina228_config_t config={BOARD_INA228_ADDRESS,BOARD_INA228_ADC_RANGE,
                                  BOARD_SHUNT_UOHM,BOARD_CURRENT_LSB_NA};
    ina228_status_t status;
    battery_sample_t sample;
    sample_buffer_reset(&window);
    if (!soc_uart_text(FIRMWARE_SENSOR_MODE ? "SIM\n" : "INA228\n")) return 1;
    if (FIRMWARE_SENSOR_MODE != 1) {
        status=ina228_init(&device,&io,&config);
        if (status!=INA228_OK) {
            (void)soc_uart_text(status==INA228_BAD_CONFIG ? "CONFIG_REQUIRED\n" : "SENSOR_INIT_ERROR\n");
            (void)soc_uart_drain();
            return 1;
        }
    }
    for (;;) {
        sample.valid=0;
        sample.cell_temperature_deci_c=0;
        sample.delta_ms=10000;
        if (FIRMWARE_SENSOR_MODE == 1) {
            /* Explicit synthetic source for simulation, never a fallback when
             * a physical sensor fails. */
            sample.voltage_mv=3402+5*((int32_t)index-10);
            sample.current_ma=-1000+24*((int32_t)(index%7u)-3);
            sample.cell_temperature_deci_c=225+2*((int32_t)(index%5u)-2);
            sample.valid=SAMPLE_HAS_VI|SAMPLE_HAS_CELL_TEMP;
        } else {
            status=ina228_read_sample(&device,&measured);
            if (status!=INA228_OK) {
                sample_buffer_reset(&window);
                last_time=0;
                (void)soc_uart_text("SENSOR_ERROR\n");
                if (FIRMWARE_SENSOR_MODE) { (void)soc_uart_drain(); return 1; }
                if (!soc_wait_cycles(SOC_CLOCK_HZ)) return 1;
                /* Recheck identity/config after disconnect or sensor reset. */
                (void)ina228_init(&device,&io,&config);
                continue;
            }
            sample.voltage_mv=measured.voltage_mv;
            sample.current_ma=measured.current_ma;
            sample.valid=SAMPLE_HAS_VI;
            if (FIRMWARE_SENSOR_MODE == 2) {
                /* Separate simulated cell-temperature source, not DIETEMP. */
                sample.cell_temperature_deci_c=225+2*((int32_t)(index%5u)-2);
                sample.valid|=SAMPLE_HAS_CELL_TEMP;
            } else {
                uint32_t now=soc_time_low();
                if (last_time) sample.delta_ms=(int32_t)((uint32_t)(now-last_time)/(SOC_CLOCK_HZ/1000u));
                last_time=now;
                if (read_cell_temperature(&sample.cell_temperature_deci_c)) sample.valid|=SAMPLE_HAS_CELL_TEMP;
            }
        }
        if (!sample_buffer_push(&window,&sample)) {
            if (!soc_uart_text("SAMPLE_GAP\n")) return 1;
        } else if (window.count==SAMPLE_WINDOW) {
            if (!sample_build_features(&window,features)) {
                if (!soc_uart_text("CELL_TEMP_REQUIRED\n")) return 1;
            } else {
                if (!soc_qnn_run(features,&result)) {
                    (void)soc_uart_text("QNN_ERROR\n");
                    (void)soc_uart_drain();
                    return 1;
                }
                if (!report_result(result)) return 1;
            }
        }
        ++index;
        if (FIRMWARE_SENSOR_MODE && index==25u) {
            if (!soc_uart_text("DONE\n") || !soc_uart_drain()) return 1;
            return 0;
        }
        if (!soc_wait_cycles(FIRMWARE_SENSOR_MODE ? 1000u : SOC_CLOCK_HZ*10u)) return 1;
    }
}
