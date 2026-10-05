package com.redhat.examples.amqp.bridge.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Verify that the AddressType enum contains the expected values.
 */
class AddressTypeTest {

    @Test
    void enumValues() {
        AddressType[] values = AddressType.values();
        assertTrue(values.length > 0, "AddressType should have at least one value");
    }

    @Test
    void valueOfTopic() {
        assertEquals(AddressType.topic, AddressType.valueOf("topic"));
    }

    @Test
    void valueOfQueue() {
        assertEquals(AddressType.queue, AddressType.valueOf("queue"));
    }
}
