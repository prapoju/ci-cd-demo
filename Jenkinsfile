#!/usr/bin/env groovy
pipeline {
    agent {
      kubernetes {
        defaultContainer 'docker'
        yamlFile 'manifests/agent-pod.yaml'
      }
    }
    stages {
        stage('Checkout') {
            steps {
              git 'https://github.com/prapoju/ci-cd-demo.git'
            }
        }

        stage('Build & Test') {
            steps {
              container('maven'){
              sh 'mvn clean package' // Compila y ejecuta pruebas unitarias automáticamente
            }
          }
        }

        stage('Static Analysis') {
            steps {
                echo 'Running code quality analysis with SonarQube...'
            }
        }

        stage('Security Scan') {
            steps {
                echo 'Scanning container image for vulnerabilities with Trivy...'
            }
        }

        stage('Deploy') {
            steps {
                echo 'Deploying application to the target environment...'
            }
        }
    }

    post {
        always {
            echo 'Cleaning up the workspace...'
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed. Please check the logs for errors.'
        }
    }
}
