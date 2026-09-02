package com.redhat.examples.mqtt.client;

import com.redhat.examples.mqtt.client.config.Mode;
import jakarta.enterprise.context.ApplicationScoped;
import org.apache.camel.builder.RouteBuilder;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class CamelConfiguration extends RouteBuilder {

  @ConfigProperty(name = "mode")
  Mode mode;

  @Override
  public void configure() throws Exception {

    //@formatter:off
    from("stream:in?promptMessage=RAW(>)&encoding=UTF-8")
      .routeId("producer").autoStartup(mode == Mode.producer)
      .to("paho-mqtt5:{{address}}");
    ;

    from("paho-mqtt5:{{address}}")
      .routeId("consumer").autoStartup(mode == Mode.consumer)
      .to("stream:out?encoding=UTF-8")
    ;
    //@formatter:on
  }
}
