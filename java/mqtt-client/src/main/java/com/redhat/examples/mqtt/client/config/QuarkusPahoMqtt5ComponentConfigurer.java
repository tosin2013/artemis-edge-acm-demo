package com.redhat.examples.mqtt.client.config;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import org.apache.camel.component.paho.mqtt5.PahoMqtt5Component;
import org.apache.camel.component.paho.mqtt5.PahoMqtt5Configuration;
import org.apache.camel.quarkus.core.events.ComponentAddEvent;

@ApplicationScoped
public class QuarkusPahoMqtt5ComponentConfigurer {

  @Inject
  PahoMqtt5Configuration pahoMqtt5Configuration;

  public void onComponentAdd(@Observes ComponentAddEvent event) {
    if (event.getComponent() instanceof PahoMqtt5Component) {
      ((PahoMqtt5Component) event.getComponent()).setConfiguration(pahoMqtt5Configuration);
    }
  }
}
