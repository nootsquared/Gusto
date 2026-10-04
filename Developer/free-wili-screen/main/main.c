#include <stdio.h>
#include <string.h>
#include "fwog_main.h"
#include "hardware/uart.h"
#include "pico/stdlib.h"
#include "climate_protocol.h"

FWOG_WATCHDOG_DEFAULT();

static fwog_link_rx_t display_receiver;
static climate_line_t uart_line;
static climate_line_t console_line;
static climate_state_t state;
static uint32_t received_count;
static uint32_t malformed_count;
static uint32_t display_sequence;
static climate_ble_state_t ble_state;
static bool ble_state_received;
static uint32_t ble_state_ms;
static bool display_ack_received;
static bool uart_ready;
static fwog_io_result_t direction_result;
static char pending_nonce[33];
static char last_ping[16] = "none";
static bool ping_pending;
static uint32_t ping_started;
static char transmit[64];
static size_t transmit_length;
static size_t transmit_position;

static uint32_t now_ms(void) {
    return to_ms_since_boot(get_absolute_time());
}

static bool queue_ble_command(const char *command) {
    if (!uart_ready || transmit_position < transmit_length) return false;
    transmit_length = (size_t)snprintf(transmit, sizeof transmit, "BLE,1,%s\n", command);
    transmit_position = 0;
    return transmit_length < sizeof transmit;
}

static void report_status(void) {
    DIAG("STATUS uart_ready=%u direction_result=%u directions_complete=%u "
         "samples=%lu malformed=%lu received=%u sequence=%lu age_ms=%lu "
         "display_ack=%u display_sequence=%lu ping=%s ble_state=%u ble_age_ms=%lu\n",
         uart_ready, (unsigned)direction_result, fwog_io_dir_last_fully_applied(),
         (unsigned long)received_count, (unsigned long)malformed_count, state.received,
         (unsigned long)state.sample.sequence,
         (unsigned long)(state.received ? now_ms() - state.received_ms : UINT32_MAX),
         display_ack_received, (unsigned long)display_sequence, last_ping,
         ble_state_received ? (unsigned)ble_state : 255u,
         (unsigned long)(ble_state_received ? now_ms() - ble_state_ms : UINT32_MAX));
}

static void console_command(const char *line) {
    if (!strcmp(line, "status")) {
        report_status();
    } else if (!strcmp(line, "ble start") || !strcmp(line, "ble stop")) {
        const char *action = !strcmp(line, "ble start") ? "START" : "STOP";
        DIAG("BLE_COMMAND %s %s\n", action,
             queue_ble_command(action) ? "queued" : "unavailable_or_busy");
    } else if (!strncmp(line, "ping ", 5) && climate_nonce_valid(line + 5)) {
        if (!uart_ready || ping_pending || transmit_position < transmit_length) {
            DIAG("PING_ERROR unavailable_or_busy\n");
            return;
        }
        strcpy(pending_nonce, line + 5);
        transmit_length = (size_t)snprintf(transmit, sizeof(transmit), "PING,1,%s\n", pending_nonce);
        transmit_position = 0;
        ping_pending = true;
        ping_started = now_ms();
        strcpy(last_ping, "pending");
        DIAG("PING_SENT %s\n", pending_nonce);
    } else if (*line) {
        DIAG("COMMAND_ERROR use_status_or_ping_nonce\n");
    }
}

static void receive_uart_line(const char *line) {
    climate_sample_t sample;
    char nonce[33];
    if (climate_parse_data(line, &sample)) {
        state.sample = sample;
        state.received_ms = now_ms();
        state.received = true;
        ++received_count;
        uint8_t payload[CLIMATE_PAYLOAD_SIZE];
        climate_encode(&sample, payload);
        if (!fwog_link_uart_send_frame(payload, sizeof(payload))) DIAG("DISPLAY_SEND_ERROR\n");
        DIAG("SAMPLE sequence=%lu uptime_ms=%lu temperature_f=%.1f humidity=%.1f "
             "light=%u valid_mask=%u\n", (unsigned long)sample.sequence,
             (unsigned long)sample.uptime_ms, sample.temperature_tenths_f / 10.0,
             sample.humidity_tenths / 10.0, sample.light_counts, sample.valid_mask);
    } else if (climate_parse_ble_state(line, &ble_state)) {
        ble_state_received = true;
        ble_state_ms = now_ms();
        uint8_t payload[3];
        climate_ble_state_encode(ble_state, payload);
        if (!fwog_link_uart_send_frame(payload, sizeof payload)) DIAG("DISPLAY_BLE_SEND_ERROR\n");
        DIAG("BLE_STATE %u\n", (unsigned)ble_state);
    } else if (climate_parse_pong(line, nonce)) {
        if (ping_pending && !strcmp(nonce, pending_nonce)) {
            ping_pending = false;
            strcpy(last_ping, "passed");
            DIAG("UART_PONG %s elapsed_ms=%lu\n", nonce, (unsigned long)(now_ms() - ping_started));
        } else DIAG("UNMATCHED_PONG %s\n", nonce);
    } else if (*line) ++malformed_count;
}

int main(void) {
    board_init();
    fwog_display_result_t display = fwog_display_update_run();
    DIAG("[climate_main] display: %s\n", fwog_display_result_text(display));
    fwog_link_rx_init(&display_receiver);
    uint32_t initialized = now_ms();
    unsigned attempts = 0;
    while (true) {
        board_watchdog_kick();
        uint32_t now = now_ms();
        if (!uart_ready && attempts < 5 && (uint32_t)(now - initialized) >= 3000) {
            ++attempts;
            initialized = now;
            fwog_io_cfg_t config;
            fwog_io_cfg_default(&config);
            config.uart_tx_out = true;
            config.uart_rx_out = false;
            direction_result = fwog_io_dir_apply(&config);
            uart_ready = direction_result == FWOG_IO_OK &&
                         fwog_io_dir_last_fully_applied() &&
                         fwog_io_config_state() == FWOG_IO_CONFIG_DISABLED;
            if (uart_ready) {
                uart_init(uart1, 115200);
                uart_set_format(uart1, 8, 1, UART_PARITY_NONE);
                uart_set_hw_flow(uart1, false, false);
                gpio_set_function(PIN_IO_UART_TX, GPIO_FUNC_UART);
                gpio_set_function(PIN_IO_UART_RX, GPIO_FUNC_UART);
                uart_set_fifo_enabled(uart1, true);
            }
            fwog_link_rx_init(&display_receiver);
            report_status();
        }
        uint8_t byte;
        size_t length;
        unsigned budget = 0;
        while (budget++ < 512 && fwog_link_uart_read(&byte)) {
            if (fwog_link_rx_byte(&display_receiver, byte, &length)) {
                uint32_t acknowledged;
                if (climate_ble_start_decode(display_receiver.buf, length)) {
                    DIAG("BLE_BUTTON_START %s\n",
                         queue_ble_command("START") ? "queued" : "unavailable_or_busy");
                } else if (climate_ack_decode(display_receiver.buf, length, &acknowledged)) {
                    display_sequence = acknowledged;
                    display_ack_received = true;
                    DIAG("DISPLAY_ACK sequence=%lu\n", (unsigned long)acknowledged);
                }
            }
        }
        budget = 0;
        while (uart_ready && budget++ < 128 && uart_is_readable(uart1)) {
            int result = climate_line_feed(&uart_line, (char)uart_getc(uart1));
            if (result == 1) receive_uart_line(uart_line.text);
            else if (result == -1) ++malformed_count;
        }
        while (uart_ready && transmit_position < transmit_length && uart_is_writable(uart1)) {
            uart_putc_raw(uart1, transmit[transmit_position++]);
        }
        budget = 0;
        int input;
        while (budget++ < 128 && (input = getchar_timeout_us(0)) != PICO_ERROR_TIMEOUT) {
            int result = climate_line_feed(&console_line, (char)input);
            if (result == 1) console_command(console_line.text);
            else if (result == -1) DIAG("COMMAND_ERROR line_too_long\n");
        }
        if (ping_pending && (uint32_t)(now_ms() - ping_started) >= 2000) {
            ping_pending = false;
            strcpy(last_ping, "timeout");
            DIAG("PING_TIMEOUT %s\n", pending_nonce);
        }
        sleep_ms(1);
    }
}
