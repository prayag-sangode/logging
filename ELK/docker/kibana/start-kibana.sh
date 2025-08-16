#!/bin/bash

echo "Waiting for Elasticsearch..."
until curl -s -k -u elastic:changeme https://elasticsearch:9200 >/dev/null 2>&1; do
  sleep 5
done

echo "Generating service token for Kibana..."
TOKEN=$(docker exec elasticsearch elasticsearch-create-enrollment-token -s kibana)
export ELASTICSEARCH_SERVICE_TOKEN=$TOKEN

echo "Starting Kibana..."
/usr/local/bin/kibana-docker
