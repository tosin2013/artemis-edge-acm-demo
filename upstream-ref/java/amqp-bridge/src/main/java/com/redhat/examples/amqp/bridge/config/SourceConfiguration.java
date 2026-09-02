package com.redhat.examples.amqp.bridge.config;

import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;

import java.net.URI;
import java.util.Optional;

@ConfigMapping(prefix = "source")
public interface SourceConfiguration {

  URI uri();

  Optional<AddressType> type();

  String address();

  String pedigree();

  @WithDefault("amqp-bridge")
  String subscriptionName();
}
