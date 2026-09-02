package com.redhat.examples.amqp.client;

import com.redhat.examples.amqp.client.config.Mode;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.jms.ConnectionFactory;
import org.apache.camel.builder.RouteBuilder;
import org.apache.qpid.jms.JmsConnectionFactory;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.net.URI;

@ApplicationScoped
public class CamelConfiguration extends RouteBuilder {

  @ConfigProperty(name = "mode")
  Mode mode;

  @ConfigProperty(name = "uri")
  URI uri;

  @Produces
  ConnectionFactory connectionFactory() {
    JmsConnectionFactory connectionFactory = new JmsConnectionFactory();
    connectionFactory.setRemoteURI(uri.toString());
    return connectionFactory;
  }

  @Override
  public void configure() throws Exception {

    //@formatter:off
    from("stream:in?promptMessage=RAW(>)&encoding=UTF-8")
      .routeId("producer").autoStartup(mode == Mode.producer)
      .to("amqp:{{type:topic}}:{{address}}")
    ;

    from("amqp:{{type:topic}}:{{address}}")
      .routeId("consumer").autoStartup(mode == Mode.consumer)
      .to("stream:out?encoding=UTF-8")
    ;
    //@formatter:on
  }
}
