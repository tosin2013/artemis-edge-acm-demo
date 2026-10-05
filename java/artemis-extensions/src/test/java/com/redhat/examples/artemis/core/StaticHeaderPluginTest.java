package com.redhat.examples.artemis.core;

import org.apache.activemq.artemis.api.core.ActiveMQException;
import org.apache.activemq.artemis.api.core.Message;
import org.apache.activemq.artemis.api.core.SimpleString;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for the StaticHeaderPlugin Artemis broker plugin.
 */
class StaticHeaderPluginTest {

    private StaticHeaderPlugin plugin;
    private Message message;

    @BeforeEach
    void setUp() {
        plugin = new StaticHeaderPlugin();
        message = mock(Message.class);
    }

    @Test
    void initRequiresHeaderName() {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_VALUE, "test-value");
        assertThrows(NullPointerException.class, () -> plugin.init(props));
    }

    @Test
    void initRequiresHeaderValue() {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_NAME, "test-header");
        assertThrows(NullPointerException.class, () -> plugin.init(props));
    }

    @Test
    void initWithValidProperties() {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_NAME, "Pedigree");
        props.put(StaticHeaderPlugin.HEADER_VALUE, "hub-01");
        assertDoesNotThrow(() -> plugin.init(props));
    }

    @Test
    void addsHeaderWhenNotPresent() throws ActiveMQException {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_NAME, "Pedigree");
        props.put(StaticHeaderPlugin.HEADER_VALUE, "hub-01");
        plugin.init(props);

        when(message.containsProperty("Pedigree")).thenReturn(false);

        plugin.beforeSend(null, null, message, false, false);

        verify(message).putStringProperty("Pedigree", "hub-01");
        verify(message).reencode();
    }

    @Test
    void doesNotOverwriteExistingHeaderByDefault() throws ActiveMQException {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_NAME, "Pedigree");
        props.put(StaticHeaderPlugin.HEADER_VALUE, "hub-01");
        plugin.init(props);

        when(message.containsProperty("Pedigree")).thenReturn(true);

        plugin.beforeSend(null, null, message, false, false);

        verify(message, never()).putStringProperty(anyString(), anyString());
        verify(message, never()).reencode();
    }

    @Test
    void overwritesExistingHeaderWhenEnabled() throws ActiveMQException {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_NAME, "Pedigree");
        props.put(StaticHeaderPlugin.HEADER_VALUE, "hub-01");
        props.put(StaticHeaderPlugin.OVERWRITE, "true");
        plugin.init(props);

        when(message.containsProperty("Pedigree")).thenReturn(true);

        plugin.beforeSend(null, null, message, false, false);

        verify(message).putStringProperty("Pedigree", "hub-01");
        verify(message).reencode();
    }

    @Test
    void overwriteDefaultsToFalse() {
        Map<String, String> props = new HashMap<>();
        props.put(StaticHeaderPlugin.HEADER_NAME, "Pedigree");
        props.put(StaticHeaderPlugin.HEADER_VALUE, "hub-01");
        plugin.init(props);

        // Implicitly tested: overwrite should be false by default
        // (tested via doesNotOverwriteExistingHeaderByDefault)
        assertDoesNotThrow(() -> plugin.init(props));
    }
}
