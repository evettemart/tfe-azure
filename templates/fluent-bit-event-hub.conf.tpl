[OUTPUT]
    Name        kafka
    Match       *
    Brokers     ${event_hub_namespace_name}.servicebus.windows.net:9093
    Topics      ${event_hub_name}
    Property    security.protocol SASL_SSL
    Property    sasl.mechanisms PLAIN
    Property    sasl.username \$ConnectionString
    Property    sasl.password ${event_hub_connection_string}
