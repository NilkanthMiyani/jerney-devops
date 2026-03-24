pipeline {
    agent any

    environment {
        IMAGE_NAME = 'my-devsecops-app'
        IMAGE_TAG  = "build-${BUILD_NUMBER}"
        // This injects the tool we configured in Step 4 directly into the pipeline
        SCANNER_HOME = tool 'sonar-scanner-cli'
    }

    stages {
        stage('1. Checkout') {
            steps {
                checkout scmGit(
                    branches: [[name: '*/main']], 
                    userRemoteConfigs: [[url: 'https://github.com/NilkanthMiyani/jerney-devops.git']]
                )
            }
        }

        stage('2. KICS (IaC Scan)') {
            steps {
                sh '''
                echo "Running KICS IaC Scan..."
                docker run --rm -u $(id -u):$(id -g) \
                -v $(pwd):/path \
                checkmarx/kics:latest scan \
                -p /path \
                -o /path \
                --report-formats "html,json,pdf" \
                --output-name "kics-report" \
                --ignore-on-exit all
                '''
            }
        }

        stage('3. SonarQube (SAST)') {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh '''
                    ${SCANNER_HOME}/bin/sonar-scanner \
                    -Dsonar.projectKey=${IMAGE_NAME} \
                    -Dsonar.sources=. \
                    -Dsonar.exclusions="**/*.html,**/*.json,**/.cache/**,**/node_modules/**"
                    '''
                }
            }
        }

        stage('4. OWASP Dependency Check (SCA)') {
            steps {
                // This securely grabs the API key we saved in Step 1
                withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_KEY')]) {
                    // This calls the native plugin instead of Docker
                    dependencyCheck additionalArguments: '''
                        --scan ./ \
                        --format HTML \
                        --format JSON \
                        --nvdApiKey $NVD_KEY \
                        --data /var/lib/jenkins/owasp-data \
                        --disableYarnAudit \
                        --disableNodeAudit
                    ''', odcInstallation: 'OWASP-DC'
                }
            }
        }

        stage('5. Docker Build (Frontend)') {
            steps {
                echo "Building Frontend Docker Image: ${IMAGE_NAME}-frontend:${IMAGE_TAG}"
                // FIXED: Added -frontend to the tag!
                sh 'docker build -t ${IMAGE_NAME}-frontend:${IMAGE_TAG} ./frontend' 
            }
        }
        
        stage('6. Docker Build (Backend)') {
            steps {
                echo "Building Backend Docker Image: ${IMAGE_NAME}-backend:${IMAGE_TAG}"
                // FIXED: Added -backend to the tag!
                sh 'docker build -t ${IMAGE_NAME}-backend:${IMAGE_TAG} ./backend' 
            }
        }

        stage('7. Trivy (Image Scan)') {
            steps {
                sh '''
                echo "1. Saving Docker image to a tar file..."
                docker save ${IMAGE_NAME}-backend:${IMAGE_TAG} -o backend-image.tar
                
                echo "2. Scanning Backend tar with Trivy..."
                docker run --rm \
                -v $(pwd):/workspace \
                aquasec/trivy:latest image \
                --format json \
                --output /workspace/trivy-report.json \
                --input /workspace/backend-image.tar
                '''
            }
        }

        stage('8. Grype (Image Scan)') {
            steps {
                sh '''
                echo "1. Downloading official Grype HTML template..."
                curl -sL https://raw.githubusercontent.com/anchore/grype/main/templates/html.tmpl -o html.tmpl
                
                echo "2. Scanning Backend tar with Grype..."
                docker run --rm \
                -v $(pwd):/workspace \
                anchore/grype:latest \
                docker-archive:/workspace/backend-image.tar \
                -o template -t /workspace/html.tmpl > grype-report.html
                '''
            }
        }
    }

    post {
        always {
            echo "Archiving all security reports..."
            archiveArtifacts artifacts: '*report*/**', allowEmptyArchive: true
            archiveArtifacts artifacts: '*.json', allowEmptyArchive: true
            archiveArtifacts artifacts: '*.html', allowEmptyArchive: true
            
            publishHTML([
                reportDir: '.',
                reportFiles: 'kics-report.html',
                reportName: 'KICS Report',
                keepAll: true,
                alwaysLinkToLastBuild: true,
                allowMissing: true
            ])
        
            publishHTML([
                reportDir: '.',
                reportFiles: 'grype-report.html',
                reportName: 'Grype Report',
                keepAll: true,
                alwaysLinkToLastBuild: true,
                allowMissing: true
            ])
            
            publishHTML([
                reportDir: '.',
                reportFiles: 'dependency-check-report.html',
                reportName: 'OWASP Dependency-Check Report',
                keepAll: true,
                alwaysLinkToLastBuild: true,
                allowMissing: true
            ])
            
            echo "Cleaning up dangling Docker images and tar to save disk space..."
            sh "docker image prune -f"
            sh "rm -f *.tar" // Cleans up the heavy tarball we created for the scans
        }
    }
}