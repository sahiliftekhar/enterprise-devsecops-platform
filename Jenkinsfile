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
    }

    /**********************************************************************
     * Environment Variables
     **********************************************************************/
    environment {

        APP_DIR = 'app'

        SONARQUBE_SERVER = 'SonarQube'

        TRIVY_REPORT = 'security-reports/trivy-fs-report.txt'

    }

    /**********************************************************************
     * Pipeline Stages
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

        stage('Build Application') {

            steps {

                dir("${APP_DIR}") {

                    sh '''
                    set -e

                    echo "Building application..."

                    npm run build
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