# EFK Stack on EKS

This guide walks through setting up the **EFK Stack** (Elasticsearch, FluentBit, Kibana) on an **EKS cluster**. The goal is to collect, process, and visualize logs from a sample application running in Kubernetes.

## Steps to Set Up

### 1. **Create EKS Cluster**

Create an EKS cluster using `eksctl`:

```bash
eksctl create cluster --name my-eks1 --region us-east-1 --version 1.30 --nodegroup-name my-nodegroup1 --node-type t2.medium --nodes 1 --nodes-min 1 --nodes-max 1 --managed --with-oidc
```

### 2. **Enable EBS CSI Addon**

Enable the Amazon EBS CSI driver for persistent storage:

```bash
eksctl create addon --name aws-ebs-csi-driver --cluster my-eks1 --region us-east-1
```

### 3. **Create Logging Namespace**

Create a Kubernetes namespace for logging:

```bash
kubectl create namespace logging
```

### 4. **Install Elasticsearch**

Create `elastic-values.yaml` for Elasticsearch configuration:

```yaml
replicas: 1
volumeClaimTemplate:
  storageClassName: gp2
persistence:
  labels:
    enabled: true
```

Install Elasticsearch using Helm:

```bash
helm repo add elastic https://helm.elastic.co
helm upgrade --install elasticsearch -f elastic-values.yaml elastic/elasticsearch -n logging --create-namespace
```

Retrieve Elasticsearch credentials:

```bash
kubectl get secrets --namespace=logging elasticsearch-master-credentials -ojsonpath='{.data.username}' | base64 -d
kubectl get secrets --namespace=logging elasticsearch-master-credentials -ojsonpath='{.data.password}' | base64 -d
```

### 5. **Scale Node Group**

Scale the EKS node group to 2 nodes for Kibana:

```bash
eksctl scale nodegroup --cluster=my-eks1 --name=my-nodegroup1 --nodes=2 --nodes-min=1 --nodes-max=2
```

### 6. **Install Kibana**

Create `kibana-values.yaml` for Kibana configuration:

```yaml
service:
  type: LoadBalancer
```

Install Kibana using Helm:

```bash
helm upgrade --install kibana -f kibana-values.yaml elastic/kibana -n logging
```

### 7. **Install FluentBit**

Create `fluentbit-values.yaml` for FluentBit configuration:

```yaml
config:
  outputs: |
    [OUTPUT]
        Name es
        Match *
        Type _doc
        Host elasticsearch-master
        Port 9200
        HTTP_User elastic
        HTTP_Passwd <password>
        tls On
        tls.verify Off
        Logstash_Format On
        Logstash_Prefix logstash
        Retry_Limit False
        Suppress_Type_Name On
```

Install FluentBit using Helm:

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit -f fluentbit-values.yaml -n logging
```

### 8. **Generate Logs from App**

Create a `deploy.yaml` file to deploy the log-app:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: log-app-config
data:
  index.html: |
    <html>
      <head><title>Log App</title></head>
      <body><h1>Welcome to the Log App</h1></body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-app
  template:
    metadata:
      labels:
        app: log-app
    spec:
      containers:
        - name: log-app
          image: httpd:2.4
          ports:
            - containerPort: 80
          volumeMounts:
            - name: app-volume
              mountPath: /usr/local/apache2/htdocs
      volumes:
        - name: app-volume
          configMap:
            name: log-app-config
---
apiVersion: v1
kind: Service
metadata:
  name: log-app-service
spec:
  selector:
    app: log-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

Deploy the application:

```bash
kubectl apply -f deploy.yaml
```

Generate logs by executing:

```bash
kubectl exec -it pod/log-app-<pod-id> -- /bin/bash
root@log-app-<pod-id>:/usr/local/apache2# while true; do curl http://localhost/; sleep 1; done
```

### 9. **Access Kibana**

Log in to Kibana using the credentials obtained earlier. Once logged in, explore the logs by selecting **"Discover"** and viewing the `logstash-*` indices.

### 10. **View Logs**

In Kibana, navigate to **Stack Management > Data Views**, add a new data view for `logstash-*` to visualize logs in Kibana's **Discover** section.

