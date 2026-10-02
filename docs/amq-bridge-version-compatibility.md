# AMQ Broker AMQP Bridge Version Compatibility

## Summary

AMQP bridge configuration via the `brokerProperties` CR array requires **AMQ Broker 7.14.1** or later. Earlier versions (7.12.x, 7.13.x) do not support this feature and will reject bridge properties with a `NoSuchMethodException`.

## Background

The Artemis Edge ACM Demo uses AMQP connections between SNO spoke brokers and regional hub brokers. These connections serve two purposes:

- **Federation** (demand-driven): Pulls messages when a consumer subscribes on the remote side. Propagation delay is ~30 seconds as the demand signal traverses the federation link.
- **Bridges** (always-on): Deterministic message routing that pushes/pulls messages immediately based on address matching policies, regardless of consumer presence.

Both federation and bridge configurations are set via `brokerProperties` — either inline in the `ActiveMQArtemis` CR array or mounted from a Secret via `extraMounts`.

## The Problem

When bridge configurations were added to the `brokerProperties` CR array for SNO spoke brokers running AMQ Broker 7.12.7, both spokes rejected the properties:

```
java.lang.NoSuchMethodException: Unknown property 'bridges' on class
'class org.apache.activemq.artemis.core.config.amqpBrokerConnectivity.AMQPBrokerConnectConfiguration'
```

The broker conditions reflected the failure:

| Condition | Status |
|---|---|
| `BrokerPropertiesApplied` | `False` / `AppliedWithError` |
| `Ready` | `False` / `WaitingForAllConditions` |

The change was immediately reverted and both SNOs recovered within 60 seconds.

## Root Cause

AMQ Broker 7.12.7 bundles **Apache Artemis ~2.38.x**. The AMQP bridge feature was added in upstream Apache Artemis via [ARTEMIS-5437](https://issues.apache.org/jira/browse/ARTEMIS-5437), which introduced the `AMQPBridgeBrokerConnectionElement` class and the `bridges` bean property on `AMQPBrokerConnectConfiguration`. This change landed in Artemis ~2.40.0+.

The `brokerProperties` mechanism uses Java bean introspection (reflection) to map property paths to setter methods. When the broker encounters `AMQPConnections.<name>.bridges.<bridge>`, it looks for a `getBridges()` method on `AMQPBrokerConnectConfiguration`. On Artemis 2.38.x, this method does not exist — hence `NoSuchMethodException`.

### Version Mapping

| AMQ Broker | Artemis Version | `bridges` Supported |
|---|---|---|
| 7.12.7 (`amq-broker-rhel8`) | ~2.38.x | No |
| 7.13.x (`amq-broker-rhel9`) | ~2.43.x | Not verified |
| 7.14.1 (`amq-broker-rhel9`) | 2.53.0.redhat-00008 | **Yes** |

## Empirical Verification

A test deployment was performed on the hub cluster using AMQ Broker 7.14.1 (`amq-broker-rhel9` operator, channel `7.14.x`, CSV `amq-broker-operator.v7.14.1-opr-1`).

### Test 1: Inline `brokerProperties` CR Array

An `ActiveMQArtemis` CR was created with both federation and bridge properties in the `spec.brokerProperties` array:

```yaml
brokerProperties:
  - "AMQPConnections.test-conn.uri=tcp://localhost:5672"
  - "AMQPConnections.test-conn.autostart=false"
  - "AMQPConnections.test-conn.federations.test-fed.type=FEDERATION"
  - "AMQPConnections.test-conn.bridges.test-bridge.type=BRIDGE"
  - "AMQPConnections.test-conn.bridges.test-bridge.bridgeFromAddressPolicies.test-from.includes.all.addressMatch=messages.#"
  - "AMQPConnections.test-conn.bridges.test-bridge.bridgeToAddressPolicies.test-to.includes.wild.addressMatch=messages.#"
```

**Result:** All conditions green.

| Condition | Status |
|---|---|
| `Valid` | `True` / `ValidationSucceeded` |
| `BrokerPropertiesApplied` | `True` / `Applied` |
| `Deployed` | `True` / `AllPodsReady` |
| `Ready` | `True` / `ResourceReady` |
| `BrokerVersionAligned` | `True` / `VersionMatch` |

Zero errors in broker logs. Zero `NoSuchMethodException`.

### Test 2: `extraMounts` Secret Pattern

A Secret containing bridge properties was created and referenced via `extraMounts.secrets`:

```yaml
spec:
  deploymentPlan:
    extraMounts:
      secrets:
        - test-714-broker-bp
```

**Result:** Broker started cleanly, bridge properties loaded with zero errors. The `BrokerPropertiesApplied` condition shows `OutOfSync` — this is expected when using `extraMounts` alone (checksum mismatch between the operator-generated empty `-props` Secret and the extraMounts file on disk). This is cosmetic, not functional.

## Resolution

The operator was upgraded from `amq-broker-rhel8` (7.12.x) to `amq-broker-rhel9` (7.14.x) across all clusters:

1. **`values.yaml`**: Added `amqBrokerOperator.name` field (configurable), changed channel from `7.12.x` to `7.14.x`
2. **Template files**: Updated 3 templates to use the configurable operator name instead of hard-coded `amq-broker-rhel8`
3. **Bridge properties**: Added AMQP bridge properties to the `snoFederationBrokerProperties` helper in `_helpers.tpl` for Mode 2 SNO deployment

## Key Takeaways

1. **Always verify feature availability against the actual AMQ Broker/Artemis version.** Red Hat product documentation may lag behind feature availability in point releases.
2. **The `brokerProperties` mechanism uses Java bean reflection.** If a property path references a class method that does not exist in the bundled Artemis version, it fails at runtime with `NoSuchMethodException`.
3. **Both `brokerProperties` CR array and `extraMounts` Secret patterns work for bridges on 7.14.1.** The inline CR array is preferred for ACM ConfigurationPolicy deployment (Mode 2) because the operator reports `BrokerPropertiesApplied: True`.
4. **Test in an isolated namespace first.** The verification was done in a separate `amq-test-714` namespace with its own OperatorGroup, avoiding any risk to production brokers.
5. **The operator package changed from `amq-broker-rhel8` to `amq-broker-rhel9`** — this is a package rename, not a simple channel change. Old Subscriptions must be manually cleaned up.
