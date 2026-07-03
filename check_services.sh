/*
===============================================================================
 Enterprise DevSecOps Platform
-------------------------------------------------------------------------------
 Version      : 1.0.0
 Pipeline     : Enterprise Continuous Integration
 Platform     : Jenkins LTS (Docker)
 Application  : Node.js (Express)
 Author       : Iftekhar Shahil
-------------------------------------------------------------------------------

 Pipeline Flow

 GitHub
    │
    ▼
 Checkout
    │
    ▼
 Verify Environment
    │
    ▼
 Install Dependencies
    │
    ▼
 Code Quality (ESLint)
    │
    ▼
 Unit Testing (Jest + Coverage)
    │
    ▼
 Dependency Audit
    │
    ▼
 SonarQube Analysis
    │
    ▼
 Quality Gate
    │
    ▼
 Trivy Filesystem Scan
    │
    ▼
 Archive Reports
===============================================================================
*/

pipeline {

    agent any

    /**********************************************************************
     * PIPELINE OPTIONS
     **********************************************************************/

    options {

        timestamps()

        ansiColor('xterm')

        disableConcurrentBuilds()

        timeout(time: 30, unit: 'MINUTES')

        buildDiscarder(
            logRotator(
                numToKeepStr: '20',
                artifactNumToKeepStr: '20'
            )
        )

    }

    /**********************************************************************
     * ENVIRONMENT VARIABLES
     **********************************************************************/

    environment {

        APP_DIR = 'app'

        REPORT_DIR = 'security-reports'

        SONARQUBE_ENV = 'SonarQube'

        TRIVY_CACHE_DIR = '.trivy-cache'

    }

    /**********************************************************************
     * STAGES
     **********************************************************************/

    stages {

        stage('Checkout Source') {

            steps {

                echo "Checking out latest source..."

                checkout scm

            }

        }

        stage('Verify Build Environment') {

            steps {

                sh '''

                set -e

                echo "======================================"
                echo " Verifying Build Environment"
                echo "======================================"

                node --version
                npm --version
                git --version
                docker --version
                trivy --version

                '''

            }

        }

        stage('Prepare Workspace') {

            steps {

                sh '''

                mkdir -p ${REPORT_DIR}

                '''

            }

        }

        stage('Install Dependencies') {

            steps {

                dir("${APP_DIR}") {

                    sh '''

                    set -e

                    echo "Installing project dependencies..."

                    npm ci

                    '''

                }

            }

        }

        stage('Static Code Analysis (ESLint)') {

            steps {

                dir("${APP_DIR}") {

                    sh '''

                    set -e

                    npm run lint

                    '''

                }

            }

        }

        stage('Unit Testing') {

            steps {

                dir("${APP_DIR}") {

                    sh '''

                    set -e

                    npm run test:ci

                    '''

                }

            }

            post {

                always {

                    junit allowEmptyResults: true,
                          testResults: '**/junit.xml'

                }

            }

        }

        stage('Dependency Audit') {

            steps {

                dir("${APP_DIR}") {

                    sh '''

                    set +e

                    npm audit --audit-level=moderate

                    '''

                }

            }

        }

        stage('SonarQube Analysis') {

            steps {

                dir("${APP_DIR}") {

                    script {

                        def scannerHome = tool 'SonarScanner'

                        withSonarQubeEnv("${SONARQUBE_ENV}") {

                            sh """

                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=enterprise-devsecops-platform \
                              -Dsonar.projectName="Enterprise DevSecOps Platform" \
                              -Dsonar.projectVersion=${BUILD_NUMBER} \
                              -Dsonar.sources=. \
                              -Dsonar.tests=test \
                              -Dsonar.test.inclusions=test/**/*.test.js \
                              -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info

                            """

                        }

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

                trivy fs . \
                  --severity HIGH,CRITICAL \
                  --format table \
                  --output security-reports/trivy-report.txt

                '''

            }

        }

        stage('Archive Reports') {

            steps {

                archiveArtifacts artifacts: 'security-reports/**/*',
                                 fingerprint: true,
                                 allowEmptyArchive: true

            }

        }

    }

    /**********************************************************************
     * POST BUILD
     **********************************************************************/

    post {

        success {

            echo ""

            echo "======================================"

            echo " Enterprise CI Pipeline Successful "

            echo "======================================"

        }

        failure {

            echo ""

            echo "======================================"

            echo " Pipeline Failed "

            echo "======================================"

        }

        always {

            cleanWs()

        }

    }

}