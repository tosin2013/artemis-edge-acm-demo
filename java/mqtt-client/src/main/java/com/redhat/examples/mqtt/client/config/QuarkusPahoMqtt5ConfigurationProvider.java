package com.redhat.examples.mqtt.client.config;

import io.quarkus.arc.All;
import io.quarkus.arc.InstanceHandle;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import org.apache.camel.component.paho.mqtt5.PahoMqtt5Configuration;
import org.apache.commons.collections4.MapUtils;
import org.eclipse.paho.mqttv5.common.packet.MqttProperties;

import javax.net.SocketFactory;
import javax.net.ssl.HostnameVerifier;
import java.util.List;

@ApplicationScoped
public class QuarkusPahoMqtt5ConfigurationProvider {

  @Inject
  @All
  List<InstanceHandle<MqttProperties>> mqttPropertiesReferences;

  @Inject
  @All
  List<InstanceHandle<SocketFactory>> socketFactoryReferences;

  @Inject
  @All
  List<InstanceHandle<HostnameVerifier>> hostnameVerifierReferences;

  private <T> T lookup(String name, List<InstanceHandle<T>> references) {
    name = name.replaceFirst("^#", "");
    T instance = null;
    for (InstanceHandle<T> instanceHandle : references) {
      if (instanceHandle.getBean().getName().equals(name)) {
        instance = instanceHandle.get();
        break;
      }
    }
    if (instance == null) {
      throw new IllegalArgumentException("Invalid MQTT properties: " + name);
    }
    return instance;
  }

  @Produces
  @Named("pahoMqtt5Configuration")
  PahoMqtt5Configuration pahoMqtt5Configuration(QuarkusPahoMqtt5Configuration quarkusConfiguration) {
    PahoMqtt5Configuration configuration = new PahoMqtt5Configuration();

    configuration.setClientId(quarkusConfiguration.clientId());
    quarkusConfiguration.brokerUrl().ifPresent(v -> configuration.setBrokerUrl(v));
    quarkusConfiguration.qos().ifPresent(v -> configuration.setQos(v));
    quarkusConfiguration.retained().ifPresent(v -> configuration.setRetained(v));
    quarkusConfiguration.persistence().ifPresent(v -> configuration.setPersistence(v));
    quarkusConfiguration.filePersistenceDirectory().ifPresent(v -> configuration.setFilePersistenceDirectory(v));
    quarkusConfiguration.keepAliveInterval().ifPresent(v -> configuration.setKeepAliveInterval(v));
    quarkusConfiguration.receiveMaximum().ifPresent(v -> configuration.setReceiveMaximum(v));
    quarkusConfiguration.willTopic().ifPresent(v -> configuration.setWillTopic(v));
    quarkusConfiguration.willPayload().ifPresent(v -> configuration.setWillPayload(v));
    quarkusConfiguration.willQos().ifPresent(v -> configuration.setWillQos(v));
    quarkusConfiguration.willRetained().ifPresent(v -> configuration.setWillRetained(v));
    quarkusConfiguration.willMqttProperties().ifPresent(v -> configuration.setWillMqttProperties(lookup(v, mqttPropertiesReferences)));
    quarkusConfiguration.userName().ifPresent(v -> configuration.setUserName(v));
    quarkusConfiguration.password().ifPresent(v -> configuration.setPassword(v));
    quarkusConfiguration.socketFactory().ifPresent(v -> configuration.setSocketFactory(lookup(v, socketFactoryReferences)));
    if (quarkusConfiguration.sslClientProps() != null && !quarkusConfiguration.sslClientProps().isEmpty()) {
      configuration.setSslClientProps(MapUtils.toProperties(quarkusConfiguration.sslClientProps()));
    }
    quarkusConfiguration.httpsHostnameVerificationEnabled().ifPresent(v -> configuration.setHttpsHostnameVerificationEnabled(v));
    quarkusConfiguration.sslHostnameVerifier().ifPresent(v -> configuration.setSslHostnameVerifier(lookup(v, hostnameVerifierReferences)));
    quarkusConfiguration.cleanStart().ifPresent(v -> configuration.setCleanStart(v));
    quarkusConfiguration.connectionTimeout().ifPresent(v -> configuration.setConnectionTimeout(v));
    quarkusConfiguration.serverURIs().ifPresent(v -> configuration.setServerURIs(v));
    quarkusConfiguration.automaticReconnect().ifPresent(v -> configuration.setAutomaticReconnect(v));
    quarkusConfiguration.maxReconnectDelay().ifPresent(v -> configuration.setMaxReconnectDelay(v));
    if (quarkusConfiguration.customWebSocketHeaders() != null && !quarkusConfiguration.customWebSocketHeaders().isEmpty()) {
      configuration.setCustomWebSocketHeaders(quarkusConfiguration.customWebSocketHeaders());
    }
    quarkusConfiguration.executorServiceTimeout().ifPresent(v -> configuration.setExecutorServiceTimeout(v));
    quarkusConfiguration.sessionExpiryInterval().ifPresent(v -> configuration.setSessionExpiryInterval(v));

    return configuration;
  }
}
