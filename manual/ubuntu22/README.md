# ELK Stack Setup on Ubuntu 22.04

This guide installs and configures **Elasticsearch**, **Kibana**, and **Logstash** with SSL and authentication enabled.
It also configures Logstash to collect **Syslog**, **SSHD**, and **Nginx** logs.

---

## Install Prerequisites

```bash
sudo apt update
sudo apt install -y apt-transport-https openjdk-11-jdk wget curl gnupg
```

---

## Add Elastic APT Repository

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update
```

---

## Install Elasticsearch

```bash
sudo apt install -y elasticsearch
```

### Configure

`/etc/elasticsearch/elasticsearch.yml`

```yaml
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

xpack.security.enabled: true
xpack.security.enrollment.enabled: true

xpack.security.http.ssl:
  enabled: true
  keystore.path: certs/http.p12

xpack.security.transport.ssl:
  enabled: true
  verification_mode: certificate
  keystore.path: certs/transport.p12
  truststore.path: certs/transport.p12

cluster.initial_master_nodes: ["elk-vm.me-west1-a.c.fiery-plate-461110-v0.internal"]

http.host: 0.0.0.0
```

### Enable & Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
```

---

## Install Kibana

```bash
sudo apt install -y kibana
```

### Configure

`/etc/kibana/kibana.yml`

```yaml
server.host: "0.0.0.0"

logging:
  appenders:
    file:
      type: file
      fileName: /var/log/kibana/kibana.log
      layout:
        type: json
  root:
    appenders:
      - default
      - file

pid.file: /run/kibana/kibana.pid

elasticsearch.hosts: [https://10.208.0.9:9200]
elasticsearch.serviceAccountToken: AAEAAWVsYXN0aWMva2liYW5hL2Vucm9sbC1wcm9jZXNzLXRva2VuLTE3NTUyODUxNDY2NzQ6Z01RX1l2UTNURy1TOHJ1ODdIS0R6dw
elasticsearch.ssl.certificateAuthorities: [/var/lib/kibana/ca_1755285147628.crt]
xpack.fleet.outputs: [{id: fleet-default-output, name: default, is_default: true, is_default_monitoring: true, type: elasticsearch, hosts: [https://10.208.0.9:9200], ca_trusted_fingerprint: b5a93263c0b49df0381b70b5bb4d5bf50195d4df738240ee5db9c9a1ffd7938e}]
```

### Enable & Start

```bash
sudo systemctl enable kibana
sudo systemctl start kibana
```

---

## Install Logstash

```bash
sudo apt install -y logstash
```

---

## Permissions & Group Fixes

Logstash must read system logs and certificates.

```bash
# Allow logstash to read system logs
sudo usermod -aG adm logstash

# Fix Elasticsearch config perms
sudo chown -R root:elasticsearch /etc/elasticsearch
sudo chmod 755 /etc/elasticsearch
sudo chown -R root:elasticsearch /etc/elasticsearch/certs
sudo chmod 750 /etc/elasticsearch/certs

# Fix Logstash pipeline folder
sudo chown -R logstash:logstash /etc/logstash/conf.d
```

Reload groups without reboot:

```bash
newgrp adm
```

---

## Logstash Pipelines

### Syslog

`/etc/logstash/conf.d/syslog.conf`

```ruby
input {
  file {
    type => "syslog"
    path => "/var/log/syslog"
    start_position => "beginning"
  }
}

filter {
  grok {
    match => { "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{HOSTNAME:syslog_host} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}" }
    tag_on_failure => [ "_grokparsefailure_syslog" ]
  }
  date {
    match => [ "syslog_timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
    target => "@timestamp"
  }
}

output {
  elasticsearch {
    hosts => ["https://localhost:9200"]
    index => "syslog-%{+YYYY.MM}"
    user => "elastic"
    password => "i+MBF+AyMwUPY7GHnQy_"
    ssl_certificate_authorities => ["/etc/elasticsearch/certs/http_ca.crt"]
  }
  stdout { codec => rubydebug }
}
```

### SSHD

`/etc/logstash/conf.d/sshd.conf`

```ruby
input {
  file {
    type => "auth_log"
    path => "/var/log/auth.log"
    start_position => "beginning"
  }
}

filter {
  grok {
    match => { "message" => "Failed %{WORD:sshd_auth_type} for %{USERNAME:sshd_invalid_user} from %{IP:sshd_client_ip} port %{NUMBER:sshd_port} %{GREEDYDATA:sshd_protocol}" }
    add_tag => [ "sshd_fail" ]
  }
}

output {
  elasticsearch {
    hosts => ["https://localhost:9200"]
    index => "sshd_fail-%{+YYYY.MM}"
    user => "elastic"
    password => "i+MBF+AyMwUPY7GHnQy_"
    ssl_certificate_authorities => ["/etc/elasticsearch/certs/http_ca.crt"]
  }
  stdout { codec => rubydebug }
}
```

### Nginx

`/etc/logstash/conf.d/nginx.conf`

```ruby
input {
  file {
    path => "/var/log/nginx/access.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
  }
  file {
    path => "/var/log/nginx/error.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
  }
}

filter {
  if [path] =~ "access.log" {
    grok {
      match => { "message" => "%{COMBINEDAPACHELOG}" }
    }
    date {
      match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ]
      target => "@timestamp"
    }
    mutate { add_field => { "log_type" => "nginx_access" } }
  }
  else if [path] =~ "error.log" {
    grok {
      match => { "message" => "\[%{HTTPDATE:timestamp}\] %{LOGLEVEL:level} %{GREEDYDATA:errormsg}" }
    }
    date {
      match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ]
      target => "@timestamp"
    }
    mutate { add_field => { "log_type" => "nginx_error" } }
  }
}

output {
  elasticsearch {
    hosts => ["https://localhost:9200"]
    index => "nginx-logs-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "i+MBF+AyMwUPY7GHnQy_"
    ssl_certificate_authorities => ["/etc/elasticsearch/certs/http_ca.crt"]
  }
  stdout { codec => rubydebug }
}
```

---

## Test & Restart Logstash

```bash
sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
sudo systemctl restart logstash
sudo journalctl -u logstash -f
```

---

## Verify in Elasticsearch

```bash
curl -u elastic:i+MBF+AyMwUPY7GHnQy_ --cacert /etc/elasticsearch/certs/http_ca.crt https://localhost:9200/_cat/indices?v
```

You should see:

* `syslog-YYYY.MM`
* `sshd_fail-YYYY.MM`
* `nginx-logs-YYYY.MM.dd`

---

Now logs flow into Elasticsearch, and you can create **Data Views** in Kibana.



Would you like me to also append **Kibana Data View creation steps** (UI walkthrough) inside this `README.md`, or keep it only server-side setup?
