#!/bin/bash
set -e

echo "Stopping services..."
systemctl stop logstash || true
systemctl stop kibana || true
systemctl stop elasticsearch || true
systemctl stop nginx || true

echo "Disabling services..."
systemctl disable logstash || true
systemctl disable kibana || true
systemctl disable elasticsearch || true
systemctl disable nginx || true

echo "Removing packages..."
apt-get remove --purge -y logstash kibana elasticsearch nginx
apt-get autoremove -y
apt-get autoclean -y

echo "Removing Elasticsearch, Kibana, Logstash, and Nginx data and config..."
rm -rf /etc/elasticsearch
rm -rf /var/lib/elasticsearch
rm -rf /var/log/elasticsearch

rm -rf /etc/kibana
rm -rf /var/lib/kibana
rm -rf /var/log/kibana

rm -rf /etc/logstash
rm -rf /var/lib/logstash
rm -rf /var/log/logstash

rm -rf /etc/nginx
rm -rf /var/log/nginx
rm -rf /var/www/html

echo "Removing users and groups..."
userdel -r logstash || true
userdel -r kibana || true
userdel -r elasticsearch || true

groupdel logstash || true
groupdel kibana || true
groupdel elasticsearch || true

echo "Removing Elasticsearch APT repository..."
rm -f /etc/apt/sources.list.d/elastic-8.x.list
rm -f /etc/apt/keyrings/GPG-KEY-elasticsearch.key

echo "Update package cache..."
apt update

echo "Cleanup complete!"
