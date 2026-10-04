#include <math.h>
#include <stdio.h>
#include <string.h>

#include "fwog_display.h"
#include "pico/stdlib.h"
#include "climate_protocol.h"

FWOG_POWER_DEFAULT();

static climate_state_t climate;
static fwog_link_rx_t main_receiver;

#define WARNING_PERIOD_MS 1500u
#define WARNING_FLASH_MS 250u
#define WARNING_BEEP_SAMPLES 1400u
#define WARNING_BEEP_HZ 391.99544f
#define WARNING_BUTTONS (FWOG_BTN_BIT(FWOG_BTN_GRAY) | \
                         FWOG_BTN_BIT(FWOG_BTN_YELLOW) | \
                         FWOG_BTN_BIT(FWOG_BTN_GREEN))

static int16_t warning_beep[WARNING_BEEP_SAMPLES];

static void prepare_warning_beep(void) {
    for (unsigned i = 0u; i < WARNING_BEEP_SAMPLES; i++) {
        unsigned gain = 40u;
        if (i < gain) {
            gain = i;
        }
        const unsigned remaining = WARNING_BEEP_SAMPLES - 1u - i;
        if (remaining < gain) {
            gain = remaining;
        }

        const float phase =
            6.28318530718f * WARNING_BEEP_HZ * (float)i / 8000.0f;

        const float tone = sinf(phase) >= 0.0f ? 1.0f : -1.0f;
        warning_beep[i] = (int16_t)(30000.0f * tone * (float)gain / 40.0f);
    }
}

static void show_warning_leds(bool lit) {
    for (unsigned i = 0u; i < FWOG_LED_COUNT; i++) {
        ws2812_set_color(i, lit ? 64u : 0u, 0u, 0u);
    }
    ws2812_process();
}

static void draw_layout(void) {
    const uint16_t background = st7789_rgb565(12, 18, 28);
    const uint16_t white = st7789_rgb565(240, 245, 255);
    const uint16_t muted = st7789_rgb565(150, 165, 185);

    st7789_clear(background);
    lcd_text_draw(16u, 4u, "CLIMATE MONITOR", 2u, white, background);
    st7789_fill_rect(16u, 26u, 288u, 2u, muted);
    lcd_text_draw(16u, 34u, "TEMPERATURE (F)", 2u, muted, background);
    lcd_text_draw(16u, 94u, "HUMIDITY (%)", 2u, muted, background);
    lcd_text_draw(16u, 154u, "AMBIENT LIGHT (COUNTS)", 2u, muted, background);
}

static void draw_warning_icon(uint16_t x, uint16_t y, bool visible) {
    static uint16_t pixels[31u * 24u];
    const uint16_t background = st7789_rgb565(12, 18, 28);
    const uint16_t red = st7789_rgb565(255, 60, 60);

    for (unsigned row = 0u; row < 24u; row++) {
        const unsigned half_width = row * 15u / 23u;
        for (unsigned col = 0u; col < 31u; col++) {
            const bool triangle = col >= 15u - half_width &&
                                  col <= 15u + half_width;
            const bool mark = col >= 14u && col <= 16u &&
                              ((row >= 8u && row <= 15u) ||
                               (row >= 19u && row <= 21u));
            pixels[row * 31u + col] =
                visible && triangle && !mark ? red : background;
        }
    }
    st7789_set_window(x, y, 31u, 24u);
    st7789_blit(pixels, 31u * 24u);
}

static void draw_reading(uint16_t y, const char *text, bool warning,
                         bool flash_on) {
    const uint16_t background = st7789_rgb565(12, 18, 28);
    const uint16_t color = warning ? st7789_rgb565(255, 60, 60) :
                                    st7789_rgb565(90, 205, 255);
    const unsigned scale = y == 52u ? 2u : 3u;
    st7789_fill_rect(16u, y, 288u, 24u, background);
    lcd_text_draw_padded(16u, y, text, 252u / (6u * scale), scale, color, background);
    if (y == 52u) {
        const char *units[2] = {strstr(text, " F"), strstr(text, " C")};
        for (unsigned i = 0; i < 2; ++i) {
            if (!units[i]) continue;
            uint16_t x = (uint16_t)(18u + (units[i] - text) * 12u);
            st7789_fill_rect(x, y + 2u, 6u, 6u, color);
            st7789_fill_rect(x + 2u, y + 4u, 2u, 2u, background);
        }
    }
    draw_warning_icon(272u, y, warning && flash_on);
}

static void draw_readings(uint32_t now, uint8_t warnings, bool flash_on) {
    char text[24];
    uint8_t valid = climate_state_fresh(&climate, now) ? climate.sample.valid_mask : 0;
    if (valid & 1) {
        double fahrenheit = climate.sample.temperature_tenths_f / 10.0;
        snprintf(text, sizeof text, "%.1f F (%.1f C)", fahrenheit, (fahrenheit - 32) * 5 / 9);
    } else strcpy(text, "--");
    draw_reading(52u, text, warnings & FWOG_BTN_BIT(FWOG_BTN_GRAY), flash_on);
    if (valid & 2) snprintf(text, sizeof text, "%.1f %%", climate.sample.humidity_tenths / 10.0);
    else strcpy(text, "--");
    draw_reading(112u, text, warnings & FWOG_BTN_BIT(FWOG_BTN_YELLOW), flash_on);
    if (valid & 4) snprintf(text, sizeof text, "%u counts", climate.sample.light_counts);
    else strcpy(text, "--");
    draw_reading(172u, text, warnings & FWOG_BTN_BIT(FWOG_BTN_GREEN), flash_on);
}

int main(void) {
    board_init();
    const bool link_ready = fwog_link_uart_init(FWOG_LINK_BAUD);
    fwog_link_rx_init(&main_receiver);
    const bool leds_ready = ws2812_init(pio0, 0u);
    show_warning_leds(false);
    prepare_warning_beep();
    const bool audio_ready = i2s_audio_init(pio0, 2u);
    if (audio_ready) {
        i2s_audio_set_volume(10);
        i2s_audio_park();
    }

    st7789_init_begin();
    const absolute_time_t lcd_deadline = make_timeout_time_ms(500);
    while (!st7789_ready() && !time_reached(lcd_deadline)) {
        fwog_power_poll(to_ms_since_boot(get_absolute_time()));
        st7789_init_step();
        sleep_ms(2);
    }

    const bool panel_ready = st7789_ready();
    if (panel_ready) {
        draw_layout();
        draw_readings(to_ms_since_boot(get_absolute_time()), 0u, false);
        st7789_dma_wait();
        board_backlight(255);
    }

    absolute_time_t next_reading = make_timeout_time_ms(1000);
    uint8_t warning_mask = 0u;
    bool flash_shown = false;
    bool leds_lit = false;
    bool power_was_armed = false;
    bool fresh_shown = false;
    uint32_t warning_cycle_ms = 0u;
    while (true) {
        const uint32_t now = to_ms_since_boot(get_absolute_time());
        const fwog_power_t power = fwog_power_poll(now);
        i2s_audio_process();
        bool sample_changed = false;
        uint8_t byte;
        size_t length;
        unsigned budget = 0;
        while (link_ready && budget++ < 512 && fwog_link_uart_read(&byte)) {
            if (!fwog_link_rx_byte(&main_receiver, byte, &length)) continue;
            if (fwog_ioexp_link_handle(main_receiver.buf, length)) continue;
            climate_sample_t sample;
            if (climate_decode(main_receiver.buf, length, &sample)) {
                climate.sample = sample;
                climate.received_ms = now;
                climate.received = true;
                sample_changed = true;
            }
        }

        bool beep_due = false;

        const uint8_t toggled = power.buttons.pressed & WARNING_BUTTONS;
        if (toggled) {
            warning_mask ^= toggled;
            if (warning_mask & toggled) {
                warning_cycle_ms = now;
                beep_due = true;
            }
            if (!warning_mask) {
                i2s_audio_stop();
            }
            DIAG("[climate_display] warning mask=0x%02x\n", (unsigned)warning_mask);
        }

        const bool warning_enabled = warning_mask != 0u;
        const uint32_t elapsed = now - warning_cycle_ms;
        if (warning_enabled && elapsed >= WARNING_PERIOD_MS) {
            warning_cycle_ms +=
                (elapsed / WARNING_PERIOD_MS) * WARNING_PERIOD_MS;
            beep_due = true;
        }
        if (beep_due && audio_ready) {
            if (!i2s_audio_is_idle()) {
                i2s_audio_stop();
            }
            if (!i2s_audio_start(warning_beep, WARNING_BEEP_SAMPLES, true, false)) {
                DIAG("[climate_display] warning beep start failed\n");
            } else {
                DIAG("[climate_display] warning beep started: G4, 175 ms\n");
            }
        }

        const bool light_on =
            warning_enabled && (now - warning_cycle_ms < WARNING_FLASH_MS);

        if (leds_ready && !power.armed &&
            (light_on != leds_lit || power_was_armed)) {
            show_warning_leds(light_on);
            leds_lit = light_on;
        }
        power_was_armed = power.armed;
        const bool refresh_due = time_reached(next_reading);
        const bool fresh = climate_state_fresh(&climate, now);
        if (panel_ready && (refresh_due || sample_changed || toggled || light_on != flash_shown || fresh != fresh_shown)) {
            draw_readings(now, warning_mask, light_on);
            st7789_dma_wait();
            if (sample_changed) {
                uint8_t acknowledgment[6];
                climate_ack_encode(climate.sample.sequence, acknowledgment);
                fwog_link_uart_send_frame(acknowledgment, sizeof acknowledgment);
            }
        }
        flash_shown = light_on;
        fresh_shown = fresh;
        if (refresh_due) {
            next_reading = make_timeout_time_ms(1000);
            DIAG("[climate_display] received=%u fresh=%u sequence=%lu mask=%u "
                 "panel=%s warnings=0x%02x leds=%s audio=%s ioexp=%u link=%u\n",
                 climate.received, climate_state_fresh(&climate, now),
                 (unsigned long)climate.sample.sequence, climate.sample.valid_mask,
                 panel_ready ? "ready" : "init-failed",
                 (unsigned)warning_mask,
                 leds_ready ? "ready" : "init-failed",
                 audio_ready ? "ready" : "init-failed", board_ioexp_ok(), link_ready);
        }
        sleep_ms(2);
    }
}
