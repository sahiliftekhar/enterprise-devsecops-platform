/*
===============================================================================
 Enterprise DevSecOps Platform
 CI Pipeline v1.0
-------------------------------------------------------------------------------
 Author  : Iftekhar Shahil
 Purpose : Enterprise Continuous Integration Pipeline
 Platform: Jenkins + SonarQube + Trivy
===============================================================================
*/

pipeline {

    agent any

    /**********************************************************************
     * Pipeline Options
     **********************************************************************/
    options {

        timestamps()

        ansiColor('xterm')

        disableConcurrentBuilds()

        buildDiscarder(logRotator(
        numToKeepStr: '10',
        artifactNumToKeepStr: '10'
        ))

        timeout(time: 30, unit: 'MINUTES')

        skipDefaultCheckout(true)

    }

    /**********************************************************************
     * Environment Variables
     **********************************************************************/
    environment {

        APP_DIR = 'app'

        GIT_BRANCH = 'main'

        GIT_REPOSITORY = 'https://github.com/sahiliftekhar/enterprise-devsecops-platform.git'

        SONARQUBE_SERVER = 'SonarQube'

        // Docker
        IMAGE_NAME = 'enterprise-devsecops-platform'
        IMAGE_TAG = "${BUILD_NUMBER}"

        // AWS
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT_ID = '035722575884'
        
        // Amazon ECR Repository
        ECR_REPOSITORY = 'enterprise-devsecops-platform'
        ECR_REGISTRY = '035722575884.dkr.ecr.ap-south-1.amazonaws.com'
        ECR_IMAGE = '035722575884.dkr.ecr.ap-south-1.amazonaws.com/enterprise-devsecops-platform'

        // Report Directories
        TRIVY_REPORT_DIR = 'security-reports/trivy-fs-report.txt'

    }

    /**********************************************************************
     * Pipeline Stages
     **********************************************************************/

    stages {

        stage('Checkout Source') {

            steps {

                echo "Checking out latest source..."

                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "*/${env.GIT_BRANCH}"]],
                    userRemoteConfigs: [[
                        url: env.GIT_REPOSITORY,
                        credentialsId: 'github-creds'
                    ]]
                ])
            }
        }

        stage('Verify Build Environment') {

            steps {

                sh '''
                set -e

                echo "===== Environment Verification ====="

                node --version
                npm --version
                git --version
                docker --version
                trivy --version

                echo "Environment verification successful."
                '''
            }
        }

        stage('Install Dependencies') {

            steps {

                dir("${APP_DIR}") {

                    sh '''
                    set -e

                    echo "Installing Node.js dependencies..."

                    npm ci
                    '''
                }
            }
        }

        stage('Validate Application') {
            steps {
                dir('app') {
                    sh '''
                    set -e

                    echo "Validating package.json..."

                    npm run

                    echo "Validation completed."
                    '''
                }
            }
        }

        stage('Run Unit Tests') {

            steps {

                dir("${APP_DIR}") {

                    sh '''
                    set -e

                    echo "Executing unit tests..."

                    npm test
                    '''
                }
            }
        }

        stage('SonarQube Analysis') {

            steps {

                dir("${APP_DIR}") {

                    withSonarQubeEnv("${SONARQUBE_SERVER}") {

                        sh '''
                        sonar-scanner \
                          -Dsonar.projectKey=enterprise-devsecops-platform \
                          -Dsonar.projectName="Enterprise DevSecOps Platform" \
                          -Dsonar.sources=. \
                          -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info
                        '''
                    }
                }
            }
        }

        stage('Quality Gate') {

            steps {

                timeout(time: 5, unit: 'MINUTES') {

                    waitForQualityGate abortPipeline: true

                }
            }
        }

        stage('Trivy Filesystem Scan') {

            steps {

                sh '''
                mkdir -p security-reports

                echo "Running Trivy Filesystem Scan..."

                trivy fs . \
                  --severity HIGH,CRITICAL \
                  --format table \
                  > security-reports/trivy-fs-report.txt
                '''
            }
        }

        stage('Build Docker Image') {

            steps {

                sh '''
                echo "Building Docker image..."

                docker build \
                -t ${IMAGE_NAME}:${IMAGE_TAG} \
                -t ${IMAGE_NAME}:latest \
                ./app

                docker images | grep ${IMAGE_NAME}
                '''
            }
        }

        stage('Trivy Image Scan') {

            steps {

                sh '''
                mkdir -p security-reports

                echo "Scanning Docker image..."

                trivy image \
                --severity HIGH,CRITICAL \
                --format table \
                ${IMAGE_NAME}:${IMAGE_TAG} \
                > security-reports/trivy-image-report.txt
                '''
            }
        }

        stage('Login to Amazon ECR') {

            steps {

                echo "Logging in to Amazon ECR..."
                echo "Using ECR Registry: ${ECR_REGISTRY}"

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-ecr-creds']
                ]) {

                    sh '''
                        aws ecr get-login-password \
                            --region ${AWS_REGION} | \
                        docker login \
                            --username AWS \
                            --password-stdin \
                            ${ECR_REGISTRY}
                    '''
                }
            }
        }

        stage('Tag Docker Image') {

            steps {

                echo "Tagging Docker image for ECR..."

                sh '''
                    docker images | grep ${IMAGE_NAME}
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_IMAGE}:${IMAGE_TAG}
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_IMAGE}:latest
                '''
            }
        }

        stage('Push Docker Image') {

            steps {

                echo "Pushing Docker image to Amazon ECR..."

                sh '''
                    docker push ${ECR_IMAGE}:${IMAGE_TAG}
                    docker push ${ECR_IMAGE}:latest
                '''
            }
        }

        stage('Archive Reports') {

            steps {

                archiveArtifacts artifacts: 'security-reports/*',
                                 fingerprint: true,
                                 allowEmptyArchive: true
            }
        }

    }

    /**********************************************************************
     * Post Actions
     **********************************************************************/

    post {

        always {

            echo "Cleaning workspace..."

            cleanWs()
        }

        success {

            echo "CI Pipeline completed successfully."
        }

        failure {

            echo "Pipeline failed. Check console logs."
        }

        unstable {

            echo "Pipeline marked as unstable."
        }

    }

}