# Install EFK Stack on Ubuntu

## Install Elasticsearch

Switch to root:

```bash
sudo su -
````

Update and add Elasticsearch GPG key:

```bash
apt update
wget https://artifacts.elastic.co/GPG-KEY-elasticsearch -O /etc/apt/keyrings/GPG-KEY-elasticsearch.key
echo "deb [signed-by=/etc/apt/keyrings/GPG-KEY-elasticsearch.key] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
apt update
```

Install Elasticsearch:

```bash
apt -y install elasticsearch
systemctl enable --now elasticsearch
systemctl status elasticsearch
sudo journalctl -u elasticsearch -f
```

While instllation password is displayed.

We can reset password if needed:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b
```

Test Elasticsearch:

```bash
curl -u elastic:<password> https://localhost:9200 -k
curl -u elastic:<password> --cacert /etc/elasticsearch/certs/http_ca.crt https://localhost:9200
```

---

## Install Kibana

Install Kibana:

```bash
apt -y install kibana
```

Generate enrollment token:

```bash
/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

Setup Kibana:

```bash
/usr/share/kibana/bin/kibana-setup --enrollment-token <token>
```

Edit `/etc/kibana/kibana.yml`:

```yaml
server.host: "0.0.0.0"
```

Enable and start Kibana:

```bash
systemctl enable --now kibana
systemctl status kibana
sudo journalctl -u kibana -f
```

---

## Install Logstash

Install Logstash:

```bash
sudo apt install -y logstash
sudo usermod -aG adm logstash
sudo systemctl enable logstash
sudo systemctl start logstash
```

Test Logstash configuration:

```bash
sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t
sudo journalctl -u logstash -f
```

---

## Configure Elasticsearch certificates for Logstash

```bash
sudo chown root:logstash /etc/elasticsearch
sudo chmod 750 /etc/elasticsearch
sudo chown -R root:logstash /etc/elasticsearch/certs
sudo chmod 750 /etc/elasticsearch/certs
sudo chmod 640 /etc/elasticsearch/certs/http_ca.crt
sudo -u logstash cat /etc/elasticsearch/certs/http_ca.crt
```

---

## Configure Logstash for syslog

Create `/etc/logstash/conf.d/syslog.conf`:

```conf
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
    password => "<password>"
    ssl_certificate_authorities => ["/etc/elasticsearch/certs/http_ca.crt"]
  }
  stdout { codec => rubydebug }
}
```

---

## Configure Logstash for SSHD failed logins

Create `/etc/logstash/conf.d/sshd.conf`:

```conf
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
    password => "<password>"
    ssl_certificate_authorities => ["/etc/elasticsearch/certs/http_ca.crt"]
  }
  stdout { codec => rubydebug }
}
```

---

## Install and test Nginx logs

Install Nginx:

```bash
sudo apt -y install nginx
sudo systemctl enable --now nginx
```

Test HTTP:

```bash
curl http://localhost/
curl http://localhost/nonexistent
```

Generate multiple logs for testing:

```bash
for i in {1..20}; do curl -s http://localhost/ >/dev/null; done
for i in {1..10}; do curl -s http://localhost/nonexistentpage >/dev/null; done
```

Configure Logstash input for Nginx logs:

```conf
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
    grok { match => { "message" => "%{COMBINEDAPACHELOG}" } }
    date { match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ] target => "@timestamp" }
    mutate { add_field => { "log_type" => "nginx_access" } }
  }
  else if [path] =~ "error.log" {
    grok { match => { "message" => "\[%{HTTPDATE:timestamp}\] %{LOGLEVEL:level} %{GREEDYDATA:errormsg}" } }
    date { match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ] target => "@timestamp" }
    mutate { add_field => { "log_type" => "nginx_error" } }
  }
}

output {
  elasticsearch {
    hosts => ["https://localhost:9200"]
    index => "nginx-logs-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "<password>"
    ssl_certificate_authorities => ["/etc/elasticsearch/certs/http_ca.crt"]
  }
  stdout { codec => rubydebug }
}
```

---

## Test Elasticsearch data using curl

```bash
curl -u elastic:<password> --cacert /etc/elasticsearch/certs/http_ca.crt "https://localhost:9200/syslog-*/_search?pretty&size=5"
curl -u elastic:<password> --cacert /etc/elasticsearch/certs/http_ca.crt "https://localhost:9200/syslog-*/_search?pretty&size=5&_source=message,syslog_host,syslog_program"
```

---

## Check Using Kibana UI

* Open your browser: http\://\<KIBANA\_HOST>:5601
* Log in using credentials (`elastic + password`)
* Go to Stack Management -> Data -> Data Views
* Click **Create data view**
* Enter index pattern: `syslog-*`
* Select Time field (`@timestamp`)
* Click **Create data view**
* Go to **Discover** to view recent logs
* Use search filters like: `syslog_program:sshd`
* Optional: create visualizations in Analytics -> Visualize Library


