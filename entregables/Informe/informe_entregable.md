# Informe Entregable: Diseño y Construcción de Pipelines CI/CD

## Tabla de Contenidos

1. [Preparación del Entorno e Infraestructura](#0-preparación-del-entorno-e-infraestructura)
2. [Configuración Inicial](#1-configuración-inicial)
3. [Definición del Pipeline](#2-definición-del-pipeline)
4. [Flujo de Pipeline Avanzado](#3-flujo-de-pipeline-avanzado)
5. [Puertas de Calidad (Gatekeeping)](#4-puertas-de-calidad-gatekeeping)
6. [Despliegue y Validación Final](#5-despliegue-y-validación-final)

---

## 0. Preparación del Entorno e Infraestructura

Antes de configurar el pipeline, fue necesario levantar la infraestructura base: un clúster Kubernetes local con `kind`, Jenkins desplegado con Helm, y SonarQube en un nodo dedicado. Los pasos que siguen reflejan lo ejecutado tal como está registrado en `manifests/script.sh`.

### 0.1 Creación del clúster con kind

```bash
kind create cluster --config kind-jenkins-config.yaml
kind get nodes -n ci-cd-demo
```

### 0.2 Instalación de Jenkins con Helm

Se agregó el repositorio oficial de Jenkins, se creó el namespace y los recursos de volumen y service account, y se instaló el chart con valores personalizados:

```bash
helm repo add jenkinsci https://charts.jenkins.io
helm repo update

kubectl apply -f jenkins/jenkins-namespace.yaml
kubectl apply -f jenkins/jenkins-01-volume.yaml
kubectl apply -f jenkins/jenkins-02-sa.yaml

helm install jenkins -n jenkins -f jenkins/jenkins-values.yaml jenkinsci/jenkins
```

El pod de Jenkins requirió ajustar permisos sobre el volumen persistente antes de arrancar correctamente:

```bash
# Corregir permisos del volumen en el nodo worker
docker exec ci-cd-demo-worker chown -R 1000:1000 /data/jenkins-volume

# Reiniciar el pod para que tome los permisos
kubectl delete pod jenkins-0 -n jenkins

# Verificar que arranca
kubectl get pods -n jenkins
```

La contraseña de administrador se obtiene decodificando el secret generado por Helm:

```bash
secret=$(kubectl get secret -n jenkins jenkins \
  -o jsonpath="{.data.jenkins-admin-password}")
echo $(echo $secret | base64 --decode)
```

### 0.3 Instalación de SonarQube con Helm

Para aislar SonarQube del tráfico de Jenkins se asignó un nodo dedicado mediante taint y label:

```bash
# Reservar el nodo para SonarQube
kubectl taint nodes ci-cd-demo-worker2 sonarqube=true:NoSchedule --overwrite
kubectl label node ci-cd-demo-worker2 sonarqube=true

# Instalar SonarQube
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update

kubectl apply -f sonarqube/sonarqube-namespace.yaml

helm upgrade --install \
  -n sonarqube \
  -f sonarqube/values.yaml \
  sonarqube sonarqube/sonarqube
```

El acceso local se habilitó con port-forward mientras no hay Ingress Controller configurado:

```bash
kubectl port-forward svc/sonarqube-sonarqube 9000:9000 -n sonarqube
```

### 0.4 Namespace y recursos de la aplicación

```bash
kubectl apply -f manifests/app/service.yml
kubectl apply -f manifests/app/deployment.yml
```

Para validar la aplicación localmente:

```bash
kubectl port-forward svc/my-app-service 8081:8080 -n app
```

---

## 1. Configuración Inicial

Esta sección documenta la preparación del entorno: instalación de plugins en Jenkins, generación de tokens de integración con SonarQube, configuración de credenciales para Docker Hub y Kubernetes, y registro del webhook entre ambas herramientas.

### 1.1 Plugins instalados en Jenkins

El plugin **SonarQube Scanner** es el puente entre Jenkins y el servidor de análisis estático. Su instalación habilita la directiva `withSonarQubeEnv` en el `Jenkinsfile` y la recepción de los resultados del Quality Gate mediante webhook.

![Plugins de SonarQube en Jenkins](./capturas/sonarqube-plugins.png)

El plugin **Kubernetes CLI** permite que el contenedor `kubectl` dentro del pod de agente autentique y ejecute comandos contra el clúster de Kubernetes usando el `kubeconfig` almacenado como credencial Jenkins.

![Plugin Kubernetes CLI en Jenkins](./capturas/kubernetes%20cliplugin.png)

### 1.2 Generación del token de SonarQube

Desde la interfaz de SonarQube se generó un token de usuario de tipo *Global Analysis Token*. Este token es el secreto que Jenkins usa para autenticar las peticiones `mvn sonar:sonar` sin exponer credenciales de usuario.

![Generación del token en SonarQube](./capturas/sonarqubegeneraciontoken.png)

![Token de SonarQube generado](./capturas/SonarQubeToken.png)

### 1.3 Credenciales en Jenkins

Las credenciales se almacenan en el *Credentials Store* de Jenkins como objetos de tipo *Secret Text* o *Username/Password*, de modo que nunca quedan expuestas en los logs del pipeline.

**Secret de SonarQube en Jenkins** — El token generado en el paso anterior se almacena aquí bajo el ID `sonarqube-token`, que es el que referencia la directiva `withSonarQubeEnv('sonarqube-server')` del Jenkinsfile.

![Secret de SonarQube en Jenkins](./capturas/sonarqube%20secretjenkins.png)

**Credenciales de Docker Hub** — Par usuario/contraseña para que el stage `Push Image` pueda hacer `docker login` y publicar la imagen sin escribir la contraseña en texto plano.

![Configuración de credenciales Docker Hub](./capturas/RegistryDockerConfig.png)

**Archivo kubeconfig en Jenkins** — El fichero `kubeconfig` del clúster se carga como credencial de tipo *Secret File* con ID `kubeconfig`, permitiendo al contenedor `kubectl` autenticarse al clúster en el stage `Deploy`.

![Archivo kubeconfig en Jenkins](./capturas/kubectlconfigfilejenkins.png)

![Configuración de kubectl en Jenkins](./capturas/kubectlconfigjenkins.png)

### 1.4 Webhook de SonarQube hacia Jenkins

El webhook notifica a Jenkins en tiempo real cuando SonarQube termina de computar el Quality Gate, permitiendo que `waitForQualityGate` no tenga que hacer *polling* activo. La URL apunta al endpoint interno `http://jenkins.jenkins.svc.cluster.local:8080/sonarqube-webhook/`.

![WebHook de SonarQube configurado](./capturas/SonarQubeWebHook.png)

---

## 2. Definición del Pipeline

El pipeline se define como **Pipeline script from SCM**: Jenkins lee el `Jenkinsfile` directamente desde el repositorio Git en cada ejecución. Esto garantiza que la definición del pipeline esté versionada junto al código fuente y que cualquier rama pueda tener su propio flujo.

### 2.1 Configuración del Job en Jenkins

La captura muestra el Job configurado con:
- **Definition:** Pipeline script from SCM
- **SCM:** Git apuntando a `https://github.com/prapoju/ci-cd-demo.git`
- **Script Path:** `Jenkinsfile` (raíz del repositorio)

![Configuración del Job en Jenkins (Pipeline from SCM)](./capturas/pipelinconfiguration.png)

### 2.2 Trigger: Poll SCM

El trigger **Poll SCM** con expresión cron `H/2 * * * *` hace que Jenkins consulte el repositorio cada dos minutos. Cuando detecta un nuevo commit, lanza automáticamente una ejecución del pipeline. El log de inicio `Started by an SCM change` confirma este comportamiento.

![Configuración de Poll SCM](./capturas/POLLSCM.png)

### 2.3 Estructura del Jenkinsfile

El `Jenkinsfile` define un pipeline declarativo con agente Kubernetes que levanta un Pod con cinco contenedores especializados:

| Contenedor | Imagen | Responsabilidad |
|---|---|---|
| `maven-jdk-11` | `maven:3.9.9-eclipse-temurin-11` | Compilación y pruebas unitarias |
| `maven-jdk-21` | `maven:3.9.9-eclipse-temurin-21` | Análisis SonarQube (requiere JDK 21) |
| `docker` | `docker:24-dind` | Build y push de imagen (Docker-in-Docker) |
| `trivy` | `aquasec/trivy:0.69.3` | Escaneo de vulnerabilidades |
| `kubectl` | `alpine/kubectl:1.36.0` | Despliegue en Kubernetes |

Las etapas del pipeline en orden son:

```
Checkout → Build & Test → Static Analysis → Quality Gate → Build Image → Security Scan → Push Image → Deploy
```

---

## 3. Flujo de Pipeline Avanzado

### 3.1 Build & Test

El stage `Build & Test` ejecuta `mvn clean package` dentro del contenedor `maven-jdk-11`. Maven compila el código fuente Java, ejecuta las pruebas unitarias con JUnit y empaqueta el artefacto JAR. El pipeline falla automáticamente si alguna prueba no pasa.

La siguiente captura muestra una ejecución inicial del pipeline antes de introducir los controles de calidad y seguridad, evidenciando que el build base funciona correctamente:

![Pipeline en estado previo al gatekeeping](./capturas/Antes_Exito.png)

### 3.2 Análisis Estático con SonarQube

El stage `Static Analysis (SonarQube)` ejecuta `mvn sonar:sonar` dentro del contenedor `maven-jdk-21` (SonarQube Scanner requiere JDK 17+). La directiva `withSonarQubeEnv('sonarqube-server')` inyecta automáticamente la URL del servidor y el token de autenticación como propiedades Maven, sin exponerlos en el log.

**Configuración del Quality Gate en SonarQube** — Define el umbral que el proyecto debe superar. El Quality Gate por defecto de SonarQube marca como *Failed* si hay nuevas vulnerabilidades, code smells críticos o cobertura insuficiente:

![Configuración del Quality Gate en SonarQube](./capturas/SonarqubeQualityGateConfig.png)

El stage `Quality Gate` en el Jenkinsfile bloquea la ejecución durante hasta 5 minutos esperando la notificación del webhook. Si SonarQube reporta *Failed*, el parámetro `abortPipeline: true` detiene el pipeline con estado de fallo:

```groovy
stage("Quality Gate") {
  steps {
    timeout(time: 5, unit: 'MINUTES') {
      waitForQualityGate abortPipeline: true
    }
  }
}
```

### 3.3 Escaneo de Vulnerabilidades con Trivy

El stage `Security Scan` usa el contenedor `trivy` para analizar la imagen Docker construida en el stage anterior. Trivy compara las capas de la imagen contra su base de datos de CVEs (Common Vulnerabilities and Exposures).

El flag `--severity CRITICAL` filtra únicamente vulnerabilidades de severidad crítica. El flag `--exit-code 0` en la configuración actual solo reporta sin abortar; en la versión con gatekeeping se cambia a `--exit-code 1` para bloquear el pipeline.

**Reporte de vulnerabilidades CRITICAL detectadas por Trivy:**

![Escaneo Trivy - vulnerabilidades detectadas](./capturas/TrivyFailure.png)

![Trivy - detalle de CVEs críticos](./capturas/TrivyFailure2.png)

![Trivy - resumen del escaneo](./capturas/TrivyFailure3.png)

---

## 4. Puertas de Calidad (Gatekeeping)

El gatekeeping convierte el pipeline de un proceso puramente descriptivo a uno que **impide el avance** del código cuando no cumple los estándares de calidad y seguridad. Se implementa en dos niveles:

### 4.1 Quality Gate de SonarQube

Cuando el análisis estático detecta vulnerabilidades o code smells que violan el Quality Gate configurado, SonarQube notifica al webhook de Jenkins con estado `FAILED`. El stage `waitForQualityGate abortPipeline: true` recibe esta notificación y aborta la ejecución.

La siguiente captura muestra el resultado en SonarQube con el Quality Gate en estado **Failed**:

![Quality Gate fallido en SonarQube](./capturas/SonarqubeQualityGateFailure.png)

La siguiente captura muestra el efecto en Jenkins: el pipeline se marca como **ABORTED/FAILED** en el stage `Quality Gate`, impidiendo que se construya o publique la imagen Docker:

![Pipeline fallido en Jenkins por Quality Gate](./capturas/FailureJenkinsQualityGate.png)

### 4.2 Gatekeeping con Trivy

Para activar el bloqueo por vulnerabilidades críticas, se cambia el flag de Trivy de `--exit-code 0` a `--exit-code 1`. Con este cambio, si Trivy encuentra al menos una CVE de severidad CRITICAL, devuelve exit code 1 y Jenkins marca el stage como fallido, deteniendo el pipeline antes del push y el despliegue:

```groovy
stage('Security Scan') {
  steps {
    container('trivy') {
      sh '''
        trivy image --severity CRITICAL --exit-code 1 $FULL_IMAGE
      '''
    }
  }
}
```

Este mecanismo garantiza que ninguna imagen con vulnerabilidades críticas conocidas llegue al registro ni al clúster de producción.

---

## 5. Despliegue y Validación Final

### 5.1 Ejecución exitosa del pipeline completo

Una vez resueltas las vulnerabilidades (actualizando dependencias o la imagen base) y satisfecho el Quality Gate de SonarQube, el pipeline completa todas las etapas satisfactoriamente. Las capturas muestran el flujo de Blue Ocean / Stage View con todos los stages en verde:

![Pipeline exitoso - vista general](./capturas/PIPELINE_EXITO1.png)

![Pipeline exitoso - todas las etapas completadas](./capturas/PIPELINEXITO2.png)

![Pipeline exitoso - ejecución final](./capturas/pipelineExito3.png)

![Pipeline exitoso - segunda ejecución exitosa](./capturas/pipeline_exito2.png)

### 5.2 Cambio en el código que desbloqueó el pipeline

La siguiente captura documenta el momento del ciclo de vida donde un ajuste en el código o en las dependencias permitió superar el Quality Gate y el escaneo de Trivy, logrando la ejecución exitosa completa del pipeline:

![Cambio que resultó en pipeline exitoso](./capturas/Cambio_Exito.png)

### 5.3 Bloque `post` y manejo de notificaciones

El bloque `post` del Jenkinsfile garantiza que siempre se ejecute una acción al finalizar el pipeline, independientemente del resultado:

```groovy
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
```

- **`always`**: Confirma la limpieza del workspace. Los pods Kubernetes son efímeros y se destruyen automáticamente al finalizar el job.
- **`success`**: Notificación de éxito; extensible para enviar mensajes a Slack/Teams o actualizar un tablero de monitoreo.
- **`failure`**: Alerta de fallo; en entornos productivos se integraría con sistemas de tickets o alertas al equipo.

---

## Conclusiones

El taller demostró la implementación de un pipeline CI/CD completo con las siguientes características:

| Característica | Herramienta | Resultado |
|---|---|---|
| Orquestación del pipeline | Jenkins + Kubernetes | Agentes efímeros en pods, sin estado persistente |
| Compilación y pruebas | Maven + JUnit | Build reproducible con pruebas automatizadas |
| Análisis estático | SonarQube | Quality Gate bloquea código con vulnerabilidades |
| Seguridad de contenedores | Trivy | Escaneo CVE previo al push de imagen |
| Publicación de imagen | Docker Hub | Imagen versionada con número de build |
| Despliegue | Kubernetes `kubectl` | Rolling update sin downtime |
| Trigger automático | Poll SCM | Detección de cambios cada 2 minutos |

El uso de **Gatekeeping** en dos niveles (SonarQube Quality Gate + Trivy exit code) es la práctica clave que transforma el pipeline de simple automatización a un sistema de **aseguramiento de calidad continua**, donde el código solo avanza hacia producción si cumple los estándares definidos.
