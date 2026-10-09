#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
/* Set these from the actual INA228 module. Zero keeps acquisition disabled;
 * simulation overrides them explicitly and never changes the board defaults. */
#ifndef BOARD_INA228_ADDRESS
#define BOARD_INA228_ADDRESS 0u
#endif
#ifndef BOARD_SHUNT_UOHM
#define BOARD_SHUNT_UOHM 0u
#endif
#ifndef BOARD_CURRENT_LSB_NA
#define BOARD_CURRENT_LSB_NA 0u
#endif
#ifndef BOARD_INA228_ADC_RANGE
#define BOARD_INA228_ADC_RANGE 0u
#endif
#ifndef FIRMWARE_SENSOR_MODE
#define FIRMWARE_SENSOR_MODE 0 /* 0=board, 1=fake samples, 2=pin-level INA228 simulation. */
#endif
#endif
