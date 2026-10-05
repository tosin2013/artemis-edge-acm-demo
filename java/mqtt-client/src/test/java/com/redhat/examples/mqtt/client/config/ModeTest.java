package com.redhat.examples.mqtt.client.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Verify that the Mode enum contains the expected values
 * and that valueOf() resolves correctly.
 */
class ModeTest {

    @Test
    void enumContainsProducerAndConsumer() {
        Mode[] values = Mode.values();
        assertEquals(2, values.length, "Mode should have exactly 2 values");
    }

    @Test
    void valueOfProducer() {
        assertEquals(Mode.producer, Mode.valueOf("producer"));
    }

    @Test
    void valueOfConsumer() {
        assertEquals(Mode.consumer, Mode.valueOf("consumer"));
    }

    @Test
    void invalidModeThrows() {
        assertThrows(IllegalArgumentException.class, () -> Mode.valueOf("bridge"));
    }
}
