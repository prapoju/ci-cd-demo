# kind
kind create cluster --config kind-jenkins-config.yaml


# helm
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
helm search repo jenkinsci

# KUBECTL
kubectl apply -f jenkins-namespace.yaml

kubectl apply -f jenkins-01-volume.yaml

# Validate volume. THe volue exist, but the node affinity is none because the resource is not required by now. When we update the file, update permises.
kubectl get pv -n jenkins


kubectl apply -f jenkins-02-sa.yaml

# Change nodeport, storageClass, service account false in the sa file
# because the sa already exist


chart=jenkinsci/jenkins
helm install jenkins -n jenkins -f jenkins-values.yaml $chart

# Get passwod
jsonpath="{.data.jenkins-admin-password}"
secret=$(kubectl get secret -n jenkins jenkins -o jsonpath=$jsonpath)
echo $(echo $secret | base64 --decode)

# cE6m2sncAcj2M8q8YaUdp9


# But there is an error because of the permises
kubectl get pods -n jenkins

# Show logs
kubectl logs jenkins-0 -n jenkins
kubectl logs jenkins-0 -n jenkins -c init

# Show the pod name
kubectl get pod jenkins-0 -n jenkins -o wide

# Change permises
docker exec jenkins-example-worker chown -R 1000:1000 /data/jenkins-volume

# Restart the pod
kubectl delete pod jenkins-0 -n jenkins

# Run this to do port forwarding
kubectl -n jenkins port-forward jenkins-0 8080:8080

# PLUGINS

# Configuere the execution of agents dinamically AGENTS-KUBERNETES. The plugin was installed before
# https://github.com/jenkinsci/kubernetes-plugin/blob/master/README.md

# Cloud kubernetes enable garbage collector. To avoid 



