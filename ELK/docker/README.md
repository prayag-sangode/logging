# ELK Stack with Docker Compose

This repository sets up a **fully automated ELK stack** with Docker Compose:

* **Elasticsearch** (v8.14.0)
* **Kibana** (v8.14.0) with automatic service token registration
* **Logstash** with pipelines for:

  * Syslog
  * SSH failed logins
  * Nginx logs
* **Nginx** for generating access and error logs

Kibana service token and enrollment are handled automatically. No manual password or token setup is required.

---

## Repository Structure

```
logging/
└── elk/
    └── docker/
        ├── docker-compose.yml
        ├── elasticsearch/
        │   └── data/          # Persistent ES data
        ├── kibana/
        │   └── start-kibana.sh
        ├── logstash/
        │   └── conf.d/
        │       ├── syslog.conf
        │       ├── sshd.conf
        │       └── nginx.conf
        └── nginx/
            └── html/
```

> All directories are created in the repo. Logstash pipelines are already present under `logstash/conf.d`.

---

## Clone the Repository

```bash
git clone https://github.com/prayag-sangode/logging.git
cd logging/elk/docker
```

---

## Set Permissions for Elasticsearch

Before starting the stack, ensure Elasticsearch can write to its data directory:

```bash
chown -R 1000:1000 ./elasticsearch/data
chmod -R 750 ./elasticsearch/data
```

> Elasticsearch container runs as UID `1000`. These permissions prevent `node locks` errors.

---

## Start the ELK Stack

```bash
docker-compose up -d
```

* **Elasticsearch** → `http://localhost:9200`
* **Kibana** → `http://localhost:5601`
* **Logstash** → ingests `/var/log/syslog`, `/var/log/auth.log`, `/var/log/nginx/*`
* **Nginx** → `http://localhost`

---

## Test Elasticsearch

**Basic connection:**

```bash
curl -u elastic:changeme -k https://localhost:9200
```

**Cluster health:**

```bash
curl -u elastic:changeme -k https://localhost:9200/_cluster/health?pretty
```

**Check indices created by Logstash:**

```bash
curl -u elastic:changeme -k "https://localhost:9200/_cat/indices?v"
```

**Query last 5 syslog messages:**

```bash
curl -u elastic:changeme -k \
"https://localhost:9200/syslog-*/_search?pretty&size=5&_source=message,syslog_host,syslog_program"
```

**Query last 5 SSH failed login attempts:**

```bash
curl -u elastic:changeme -k \
"https://localhost:9200/sshd_fail-*/_search?pretty&size=5&_source=message,sshd_invalid_user,sshd_client_ip"
```

**Query last 5 Nginx access logs:**

```bash
curl -u elastic:changeme -k \
"https://localhost:9200/nginx-logs-*/_search?pretty&size=5&_source=message,log_type"
```

---

## Kibana Enrollment (Automatic)

Kibana automatically waits for Elasticsearch and retrieves a **service token** to enroll itself:

```bash
docker exec -it elasticsearch \
/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

This token is then used by `start-kibana.sh`:

```bash
/usr/share/kibana/bin/kibana-setup --enrollment-token <TOKEN>
```

After this, Kibana starts without asking for login tokens every time.

---

## Troubleshooting

**Elasticsearch node lock error:**

```
failed to obtain node locks, tried [/usr/share/elasticsearch/data]
```

Fix:

```bash
docker-compose down
rm -rf ./elasticsearch/data/*
chown -R 1000:1000 ./elasticsearch/data
chmod -R 750 ./elasticsearch/data
docker-compose up -d
```

---

## Cleanup Script (Optional)

If you want to start fresh:

```bash
docker-compose down -v
rm -rf ./elasticsearch/data/*
```



Do you want me to create that script next?

