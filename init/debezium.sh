#!/bin/bash
# Starts Kafka Connect and registers the BuildingPro Suites CDC connector once Connect answers.
/docker-entrypoint.sh start &
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8083/connectors)" = "200" ]; do sleep 2; done
curl -s -X DELETE http://localhost:8083/connectors/eliona-connector >/dev/null
curl -s -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ -d @/eliona-connector.json
wait
