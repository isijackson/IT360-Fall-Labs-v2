pipeline {
    agent any
    environment {
        IMAGE_NAME = "${env.IMAGE_NAME ?: 'YOUR_DOCKERHUB_USER/menu-board'}"
        REGISTRY   = "${env.REGISTRY_URL ?: 'https://index.docker.io/v1/'}"
    }
    stages {
        stage('Checkout') {
            steps { checkout scm }
        }
        stage('Build') {
            steps { script { docker.build("${IMAGE_NAME}:${BUILD_NUMBER}") } }
        }
        stage('Smoke test') {
            // Run the freshly built image and fetch its home page; a non-200 fails the build before any push.
            // On a Jenkins VM the container is reached on localhost:18080. When Jenkins itself runs in Docker
            // (SMOKE_NET set), it is reached by container name over that Docker network instead.
            steps {
                script {
                    def net  = env.SMOKE_NET ? "--network ${env.SMOKE_NET}" : ""
                    def url  = env.SMOKE_NET ? "http://smoke-${BUILD_NUMBER}/" : "http://localhost:18080/"
                    docker.image("${IMAGE_NAME}:${BUILD_NUMBER}").withRun("-p 18080:80 --name smoke-${BUILD_NUMBER} ${net}") { c ->
                        sh "sleep 2; curl -sf -o /dev/null -w 'HTTP %{http_code}\\n' ${url}"
                    }
                }
            }
        }
        stage('Push') {
            steps {
                script {
                    docker.withRegistry(REGISTRY, 'dockerhub-credentials') {
                        def img = docker.image("${IMAGE_NAME}:${BUILD_NUMBER}")
                        img.push("${BUILD_NUMBER}")
                        img.push('latest')
                    }
                }
            }
        }
    }
}
