package com.redhat.examples.amqp.bridge.config;

import io.smallrye.config.ConfigMapping;

import java.net.URI;
import java.util.Optional;

@ConfigMapping(prefix = "target")
public interface TargetConfiguration {

  URI uri();

  Optional<AddressType> type();

  String pedigree();
}
