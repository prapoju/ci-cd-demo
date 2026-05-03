#!/usr/bin/env groovy
pipeline {
    agent {
      kubernetes {
        defaultContainer 'docker'
        yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          containers:
            - name: maven-jdk-11
              image: maven:3.9.9-eclipse-temurin-11
              command: ["sleep"]
              args: ["infinity"]
            - name: docker
              image: docker:24-dind
              securityContext:
                privileged: true
              env:
                - name: DOCKER_TLS_CERTDIR
                  value: ""
              ports:
                - containerPort: 2375
              command: ["dockerd-entrypoint.sh"]
              args: ["--host=tcp://0.0.0.0:2375","--host=unix:///var/run/docker.sock"]
            - name: maven-jdk-21
              image: maven:3.9.9-eclipse-temurin-21
              command: ["sleep"]
              args: ["infinity"]
            - name: trivy
              image: aquasec/trivy:0.69.3
              env:
                - name: DOCKER_HOST
                  value: tcp://localhost:2375
              command: ["sleep"]
              args: ["infinity"]
            - name: kubectl
              image: alpine/kubectl:1.36.0
              command: ["cat"]
              tty: true
        '''
      }
    }

    environment {
        REGISTRY   = 'docker.io'
        IMAGE_REPO = 'prapoju/my-app'
        IMAGE_TAG  = "${env.BUILD_NUMBER}"
        FULL_IMAGE = "${REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}"
    }

    stages {
        stage('Checkout') {
            steps {
              git 'https://github.com/prapoju/ci-cd-demo.git'
            }
        }

        stage('Build & Test') {
            steps {
              container('maven-jdk-11'){
              sh 'mvn clean package' // Compila y ejecuta pruebas unitarias automáticamente
            }
          }
        }

        stage('Static Analysis (SonarQube)') {
          steps {
            echo 'Running code quality analysis with SonarQube...'
            container('maven-jdk-21') {
              withSonarQubeEnv('sonarqube-server') {
                sh '''
                  mvn sonar:sonar \
                    -Dsonar.projectKey=my-app
                '''
              }
            }
          }
        }
        stage("Quality Gate") {
            steps {
              timeout(time: 5, unit: 'MINUTES') {
                waitForQualityGate abortPipeline: true
              }
            }
        }


        stage('Build Image') {
          steps {
            container('docker') {
              withCredentials([usernamePassword(
                credentialsId: 'dockerhub-credentials',
                usernameVariable: 'DOCKER_USER',
                passwordVariable: 'DOCKER_PASS'
              )]) {
                sh '''
                  docker build -t $FULL_IMAGE .
                  echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                  docker push $FULL_IMAGE
                '''
              }
            }
          }
        }
        
        stage('Security Scan') {
            steps {
              container('trivy') {
              sh '''
                  trivy image --severity CRITICAL --exit-code 1 my-app:latest
               '''
              }
            }
        }

        stage('Deploy') {
            steps {
                container('kubectl') {
                    withKubeConfig(credentialsId: 'kubeconfig') {
                        sh '''
                          sed "s|IMAGE_NAME|$FULL_IMAGE|g" manifests/app/deployment.yml | kubectl apply -f -
                          kubectl apply -f manifests/app/service.yml
                          kubectl rollout status deployment/my-app-deployment -n app 
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            echo 'The workspace will be deleted. The pods are temporal.'
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed. Please check the logs for errors.'
        }
    }
}
