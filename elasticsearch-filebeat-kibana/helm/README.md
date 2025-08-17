# Elasticsearch, Filebeat and Kibana installation on K8s

## Add Elastic Helm Repo

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
````

---

## Deploy Elasticsearch

Create a values file:

```bash
cat > elasticsearch-values.yaml <<EOF
replicas: 1
minimumMasterNodes: 1
EOF
```

Install Elasticsearch:

```bash
helm upgrade --install elasticsearch elastic/elasticsearch -f elasticsearch-values.yaml -n logging --create-namespace
```

Retrieve Elasticsearch credentials:

```bash
kubectl -n logging get secret elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d ; echo
```

---

## Test Elasticsearch Access with Nginx

Create an Nginx deployment:

```bash
kubectl create deployment my-nginx --image=nginx
kubectl exec -it deployment.apps/my-nginx -- /bin/bash
```

Inside the pod, install curl and test:

```bash
apt update && apt -y install curl
curl -u "elastic:<ELASTIC_PASSWORD>" -k https://elasticsearch-master.logging.svc.cluster.local:9200
```

---

## Deploy Kibana

Create a values file:

```bash
cat > kibana-values.yaml <<EOF
service:
  type: NodePort
  # type: LoadBalancer
EOF
```

Install Kibana:

```bash
helm upgrade --install kibana elastic/kibana -n logging -f kibana-values.yaml
```

---

## Deploy Filebeat

```bash
helm upgrade --install filebeat elastic/filebeat -n logging
```

---

## Configure Kibana Data View

1. Open Kibana UI
2. Go to **Discover → Create data view**
3. Fill in:

   * **Name:** `logs`
   * **Index pattern:** `filebeat-8.5.1`
   * **Timestamp field:** `@timestamp`
4. Click **Save data view**

---

## Test Nginx Error Logs

Create a new namespace and Nginx deployment:

```bash
kubectl create ns dev
kubectl create deployment my-nginx --image=nginx -n dev
kubectl -n dev exec -it deployment.apps/my-nginx -- /bin/bash
```

Generate error logs:

```bash
curl http://localhost/not-existing-page
curl http://localhost/secret/ --header "Host: forbidden.com"
curl http://localhost/cgi-bin/test
```

Check logs:

```bash
kubectl -n dev logs deployment.apps/my-nginx
```

---

## Search Nginx Errors in Kibana

Use the following query in Kibana Discover:

```kql
kubernetes.container.name : "nginx" and message : "*error*" and kubernetes.namespace : "dev"
```

This will show all Nginx error logs from the `dev` namespace.

---

## Notes

* Ensure Filebeat is running as a DaemonSet and has access to container logs.
* Elasticsearch credentials are required if security is enabled.
* Use `https` and `-k` flag with curl to ignore self-signed certificates.



Do you want me to do that next?
```
