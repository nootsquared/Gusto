#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "climate_protocol.h"

static void invalid(const char *text) {
    climate_sample_t sample = {0};
    assert(!climate_parse_data(text, &sample));
}

static void test_records(void) {
    climate_sample_t sample;
    assert(climate_parse_data("DATA,1,42,123456,72.5,45.0,320,7", &sample));
    assert(sample.sequence == 42 && sample.uptime_ms == 123456);
    assert(sample.temperature_tenths_f == 725 && sample.humidity_tenths == 450);
    assert(sample.light_counts == 320 && sample.valid_mask == 7);
    assert(climate_parse_data("DATA,1,4294967295,4294967295,-40.0,100.0,65535,7", &sample));
    assert(sample.sequence == UINT32_MAX && sample.temperature_tenths_f == -400);
    assert(climate_parse_data("DATA,1,0,0,185.0,0.0,0,7", &sample));
    assert(climate_parse_data("DATA,1,0,0,NA,NA,NA,0", &sample));
    assert(sample.valid_mask == 0);
    assert(climate_parse_data("DATA,1,0,0,NA,50.0,NA,2", &sample));
    invalid("DATA,2,1,2,72.5,45.0,320,7");
    invalid("DATA,1,1,2,72.5,45.0,320");
    invalid("DATA,1,1,2,72.5,45.0,320,7,extra");
    invalid("DATA,1,1,2,72.5,,320,7");
    invalid("DATA,1,1,2,nan,45.0,320,7");
    invalid("DATA,1,1,2,inf,45.0,320,7");
    invalid("DATA,1,1,2,NA,45.0,320,7");
    invalid("DATA,1,1,2,72.5,NA,320,7");
    invalid("DATA,1,1,2,72.5,45.0,NA,7");
    invalid("DATA,1,1,2,72.5,45.0,320,0");
    invalid("DATA,1,1,2,-40.1,45.0,320,7");
    invalid("DATA,1,1,2,185.1,45.0,320,7");
    invalid("DATA,1,1,2,72.5,100.1,320,7");
    invalid("DATA,1,1,2,72.5,-0.1,320,7");
    invalid("DATA,1,1,2,72.5,45.0,65536,7");
    invalid("DATA,1,1,2,72.5,45.0,-1,7");
    invalid("DATA,1,4294967296,2,72.5,45.0,320,7");
    invalid("DATA,1,1,4294967296,72.5,45.0,320,7");
    invalid("DATA,1,1,2,72.5,45.0,320,8");
    invalid("DATA,1,1,2,72.50,45.0,320,7");
    invalid("DATA,1,1,2,72.5x,45.0,320,7");
    invalid("DATA,1,1,2,72.5,45.0,320,999999999999999");
}

static void test_stream(void) {
    climate_line_t line = {0};
    const char *records = "DATA,1,1,1000,72.5,45.0,320,7\r\nDATA,1,2,2000,72.5,45.0,320,7\n";
    unsigned completed = 0;
    climate_sample_t sample;
    for (size_t i = 0; records[i]; ++i) {
        int result = climate_line_feed(&line, records[i]);
        if (result == 1) {
            assert(climate_parse_data(line.text, &sample));
            assert(sample.sequence == ++completed);
        } else assert(result == 0);
    }
    assert(completed == 2);
    for (unsigned i = 0; i < 200; ++i) assert(climate_line_feed(&line, 'A') == 0);
    assert(climate_line_feed(&line, '\n') == -1);
    const char *ping = "PONG,1,abc_42\r\n";
    for (size_t i = 0; ping[i]; ++i) {
        int result = climate_line_feed(&line, ping[i]);
        if (result == 1) {
            char nonce[33];
            assert(climate_parse_pong(line.text, nonce));
            assert(!strcmp(nonce, "abc_42"));
        }
    }
    assert(climate_line_feed(&line, 0) == 0);
    assert(climate_line_feed(&line, '\n') == -1);
}

static void test_payload_and_age(void) {
    climate_sample_t sample, decoded;
    assert(climate_parse_data("DATA,1,4294967295,10,-40.0,100.0,65535,7", &sample));
    uint8_t payload[CLIMATE_PAYLOAD_SIZE];
    climate_encode(&sample, payload);
    assert(payload[0] == 0x30 && payload[1] == 1 && payload[2] == 255);
    assert(payload[10] == 0x70 && payload[11] == 0xfe);
    assert(climate_decode(payload, sizeof(payload), &decoded));
    assert(decoded.sequence == sample.sequence);
    assert(decoded.temperature_tenths_f == -400 && decoded.humidity_tenths == 1000);
    assert(decoded.light_counts == 65535);
    assert(!climate_decode(payload, sizeof(payload) - 1, &decoded));
    payload[1] = 2;
    assert(!climate_decode(payload, sizeof(payload), &decoded));
    uint8_t ack[6];
    uint32_t sequence;
    climate_ack_encode(UINT32_MAX, ack);
    assert(climate_ack_decode(ack, sizeof(ack), &sequence) && sequence == UINT32_MAX);
    assert(!climate_ack_decode(ack, 5, &sequence));
    climate_state_t state = {0};
    assert(!climate_state_fresh(&state, 0));
    state.received = true;
    state.received_ms = UINT32_MAX - 100;
    assert(climate_state_fresh(&state, 100));
    assert(!climate_state_fresh(&state, 4899));
    state.received_ms = 5000;
    assert(climate_state_fresh(&state, 9999));
    assert(!climate_state_fresh(&state, 10000));
    state.received_ms = 10001;
    assert(climate_state_fresh(&state, 10001));
}

static void test_ping(void) {
    char nonce[33];
    assert(climate_parse_pong("PONG,1,test_42", nonce));
    assert(!strcmp(nonce, "test_42"));
    assert(!climate_parse_pong("PONG,2,test_42", nonce));
    assert(!climate_parse_pong("PONG,1,", nonce));
    assert(!climate_parse_pong("PONG,1,test,extra", nonce));
    assert(!climate_nonce_valid("a b"));
    assert(!climate_nonce_valid("123456789012345678901234567890123"));
}

int main(void) {
    test_records();
    test_stream();
    test_payload_and_age();
    test_ping();
    puts("PASS: receiver parsing, stream recovery, boundaries, NA/masks, payload/ack encoding, stale recovery and nonce validation");
    return 0;
}
