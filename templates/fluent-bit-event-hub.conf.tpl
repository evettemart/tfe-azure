[OUTPUT]
    Name                      kafka
    Match                     *
    Brokers                   ${event_hub_namespace_name}.servicebus.windows.net:9093
    Topics                    ${event_hub_name}
    rdkafka.security.protocol SASL_SSL
    rdkafka.sasl.mechanisms   PLAIN
    rdkafka.sasl.username     \$ConnectionString
    rdkafka.sasl.password     ${event_hub_connection_string}
