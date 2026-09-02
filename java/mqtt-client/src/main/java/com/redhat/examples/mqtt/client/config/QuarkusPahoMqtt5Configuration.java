package com.redhat.examples.mqtt.client.config;

import io.smallrye.config.ConfigMapping;
import org.apache.camel.component.paho.mqtt5.PahoMqtt5Persistence;

import java.util.Map;
import java.util.Optional;

@ConfigMapping(prefix = "mqtt")
public interface QuarkusPahoMqtt5Configuration {

  String clientId();

  Optional<String> brokerUrl();

  Optional<Integer> qos();

  Optional<Boolean> retained();

  Optional<PahoMqtt5Persistence> persistence();

  Optional<String> filePersistenceDirectory();

  Optional<Integer> keepAliveInterval();

  Optional<Integer> receiveMaximum();

  Optional<String> willTopic();

  Optional<String> willPayload();

  Optional<Integer> willQos();

  Optional<Boolean> willRetained();

  Optional<String> willMqttProperties();

  Optional<String> userName();

  Optional<String> password();

  Optional<String> socketFactory();

  Map<String, String> sslClientProps();

  Optional<Boolean> httpsHostnameVerificationEnabled();

  Optional<String> sslHostnameVerifier();

  Optional<Boolean> cleanStart();

  Optional<Integer> connectionTimeout();

  Optional<String> serverURIs();

  Optional<Boolean> automaticReconnect();

  Optional<Integer> maxReconnectDelay();

  Map<String, String> customWebSocketHeaders();

  Optional<Integer> executorServiceTimeout();

  Optional<Long> sessionExpiryInterval();
}
