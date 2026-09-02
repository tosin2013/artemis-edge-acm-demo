package com.redhat.examples.artemis.core;

import org.apache.activemq.artemis.api.core.ActiveMQException;
import org.apache.activemq.artemis.api.core.Message;
import org.apache.activemq.artemis.core.server.ServerSession;
import org.apache.activemq.artemis.core.server.plugin.ActiveMQServerPlugin;
import org.apache.activemq.artemis.core.transaction.Transaction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.Objects;

public class StaticHeaderPlugin implements ActiveMQServerPlugin {

  private static final Logger log = LoggerFactory.getLogger(StaticHeaderPlugin.class);

  public static final String HEADER_NAME = "HEADER_NAME";
  public static final String HEADER_VALUE = "HEADER_VALUE";
  public static final String OVERWRITE = "OVERWRITE";

  private String headerName;
  private String headerValue;
  private boolean overwrite;

  @Override
  public void init(Map<String, String> properties) {
    this.headerName = Objects.requireNonNull(properties.get(HEADER_NAME), "The " + HEADER_NAME + " property is required");
    this.headerValue = Objects.requireNonNull(properties.get(HEADER_VALUE), "The " + HEADER_VALUE + " property is required");
    this.overwrite = Boolean.parseBoolean(properties.getOrDefault(OVERWRITE, "false"));
  }

  @Override
  public void beforeSend(ServerSession session, Transaction tx, Message message, boolean direct, boolean noAutoCreateQueue) throws ActiveMQException {
    if (!message.containsProperty(headerName) || overwrite) {
      log.info("Adding header: [{}={}]", headerName, headerValue);
      message.putStringProperty(headerName, headerValue);
      message.reencode();
    }
  }
}
