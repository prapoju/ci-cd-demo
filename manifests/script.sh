# kind: Create the cluster
kind create cluster --config kind-jenkins-config.yaml

# validate nodes creation
kind get nodes -n ci-cd-demo


# helm
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
helm search repo jenkinsci

# KUBECTL
kubectl apply -f jenkins/jenkins-namespace.yaml

kubectl apply -f jenkins/jenkins-01-volume.yaml

# Validate volume. THe volue exist, but the node affinity is none because the resource is not required by now. When we update the file, update permises.
kubectl get pv -n jenkins


kubectl apply -f jenkins/jenkins-02-sa.yaml

# Change nodeport, storageClass, service account false in the sa file
# because the sa already exist

# Define de chart
# Create a release called jenkins in the name space jenkins that overrides the default conifg
# using the jenkins-values.yaml and uses the chart

chart=jenkinsci/jenkins
helm install jenkins -n jenkins -f jenkins/jenkins-values.yaml $chart

# Get passwod
jsonpath="{.data.jenkins-admin-password}"
secret=$(kubectl get secret -n jenkins jenkins -o jsonpath=$jsonpath)
echo $(echo $secret | base64 --decode)

# Example password
# p3hks5SgdQOF78PBbW8uwg


# But there is an error because of the permises
kubectl get pods -n jenkins

# Show logs
kubectl logs jenkins-0 -n jenkins
kubectl logs jenkins-0 -n jenkins -c init

# Show the pod name
kubectl get pod jenkins-0 -n jenkins -o wide

# Change permises
docker exec ci-cd-demo-worker  chown -R 1000:1000 /data/jenkins-volume

# Restart the pod
kubectl delete pod jenkins-0 -n jenkins

# wait until the status is running
kubectl get pods -n jenkins

# get the password again if you can't sign in as admin
kubectl -n jenkins port-forward jenkins-0 8080:8080

# Or configure the ingress contoller https://docs.nginx.com/nginx-ingress-controller/install/helm/open-source/

# kubectl apply -f ingress-nginx/ingress-namespace.yaml

# helm install -n ingress-nginx nginx-ingress-controller oci://ghcr.io/nginx/charts/nginx-ingress --version 2.5.1

# kubectl get ingressclasses
# The class name is nginx. No you can apply the cofiguration
# kubectl apply -f jenkins/jenkins-ingress.yaml



# sonarqube

kubectl get nodes
kubectl get pods -n jenkins -o wide

# To enter in a pod run 
# kubectl exec -n <namespace> --stdin --tty <pod>  -- /bin/bash
# kubectl exec -n jenkins --stdin --tty jenkins-agent-debug -c maven-jdk-11 -- /bin/bash  

# Choose a node name preferably not used by the jenkins pod. In my case it was ci-cd-demo-worker2
#
# we stop kubernetes from scheduling pods in the node
kubectl taint nodes ci-cd-demo-worker2 sonarqube=true:NoSchedule --overwrite

kubectl label node ci-cd-demo-worker2 sonarqube=true
# Rules in the values.yaml
# - sonarqube ignores the tail rule
# - sonarqube uses nodes labeled as sonarqube
# - monitoring passcode
# - community edition enabled

helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube

helm repo update

kubectl apply -f sonarqube/sonarqube-namespace.yaml

helm upgrade --install \
  -n sonarqube \
  -f sonarqube/values.yaml \
  sonarqube sonarqube/sonarqube

# Wait for 5 minutes
kubectl get pods -n sonarqube -o wide

# Get your token. By ingressing to the page. It is possible to use the ingress controller
#

kubectl port-forward svc/sonarqube-sonarqube 9000:9000 -n sonarqube

# Generate your token
# Example: sqa_94a2eea9c7d8524f352be0aa97c2f6633b466c0e
# Manage jenkins, system SONARQUBE SERVERS,
# Server URL http://sonarqube-sonarqube.sonarqube:9000
# Add secret  text paste secret scope global
#
#
# Configure the webhook
# Install sonarqube quality gate plugin
# 1) Create the web hook for the project cicd-demo. its key is my-app. If the project
# doesn't exist run the pipeline and check again.
# Read https://v1-32.docs.kubernetes.io/docs/concepts/services-networking/dns-pod-service/
# https://www.jenkins.io/doc/pipeline/steps/sonar/
# Project settings, webhooks create
# Name: jenkins-agent
# url: http://jenkins.jenkins.svc.cluster.local:8080/sonarqube-webhook/
# kubectl exec -it sonarqube-sonarqube-0 -n sonarqube -- sh
# Now add the quality gate configuration
# Manage jenkins
# Quality gate sonar qube
# Sonaqube url http://sonarqube-sonarqube.sonarqube:9000
# Token: The token that we used previously
# 2) Add quality gate condition. Add condition security hospots reviewed is less than 100
# 3) Go to the project quality gate always use a specific quality gate and add it.


# Apply the service yaml
kubectl apply -f manifests/app/service.yml

# Apply the deployment
kubectl apply -f manifests/app/deployment.yml



