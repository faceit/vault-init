#!/usr/bin/env groovy
// These are general variable used in the script

def releaseVersion = ''
def my_jenkins_file_version = '7'
def release_to_dev_env = 'false'

pipeline {
    // An agent will be created and linked to the pipeline run
    agent {
        label 'backend'
    }

    options {
        // Because of how semantic release plugin works, we don't want the automatic checkout but we want to be able to push changes to the master
        skipDefaultCheckout()

        // Discard old builds to not clog up jenkins
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '10'))

        // We don't want two builds to run at the same time. This allows builds for different branches to run at the same time.
        disableConcurrentBuilds()
    }

    environment {
        // Env Variable to change for specific projects
        PROJECT_NAME = "vault-init"
        NEW_RELIC_APP_ID="-1"

        // There will be a refactor at some point for moving these
        GITHUB_TOKEN = credentials('faceitdev-github-personal-token')
    }

    stages {
        // Clearing the workspace
        stage ('Clean') {
            steps {
                script {
                    // This check is needed if we want to release some very important updates in this file
                    if (my_jenkins_file_version < env.JENKINS_FILE_VERSION) {
                        error("Jenkins file env version is different - please update your Jenkinsfile!")
                    }
                }
                deleteDir()
            }
        }

        // Doing the manual checkout
        stage ('Checkout') {
            steps {
                checkout scm
            }
        }

        // Semantic release version calculation
        // if the branch is not the master branch, then the version is calculated as a git commit hash so that we still can have unique artifacts
        stage('Calculating version') {
            environment {
                SEMANTIC_VERSION_PATH = tool name: 'semantic-version', type: 'com.cloudbees.jenkins.plugins.customtools.CustomTool'
            }

            steps {
                script {
                    if (env.BRANCH_NAME == 'master') {
                        sh """
                        git checkout master
                        ${SEMANTIC_VERSION_PATH}/semantic-version \
                            -slug ${env.ORG}/${PROJECT_NAME} \
                            -vf \
                            -changelog CHANGELOG.md
                        """
                        script {
                            releaseVersion = sh(returnStdout: true, script: 'cat .version')
                        }
                    } else {
                        releaseVersion = sh(returnStdout: true, script: 'git rev-parse HEAD').trim().take(14)
                    }
                }
                sh """
                echo "Version will be ${releaseVersion}"
                """
            }
        }

        // Building the application
        stage('Build') {
            agent {
                // Use golang
                docker {
                    image 'gcr.io/docker-images-214113/golang:1.11'
                    registryCredentialsId 'gcr:docker-images-214113'
                    registryUrl 'https://gcr.io'
                    reuseNode true
                    args '-u jenkins:jenkins -v ${WORKSPACE}:/go/src/github.com/faceit/${PROJECT_NAME}'
                }
            }

            steps {
                sshagent (credentials: ['git-ssh-key']) {
                    sh """
                    echo "Building ${env.ORG}/${PROJECT_NAME} - version ${releaseVersion}"
                    cd /go/src/github.com/${env.ORG}/${PROJECT_NAME} && VERSION=${releaseVersion} make all
                    """
                }
            }
        }

        stage('Docker Build and Push') {
            steps {
                // All of this is exposing the service account credentials and setting up Google Cloud SDK with temporary credentials
                // Otherwise every other execution on this slave would share the same credentials
                withCredentials([file(credentialsId: 'jenkins-development-service-account', variable: 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE')]) {
                    withEnv(['CLOUDSDK_CONFIG=/home/jenkins/gcloud-development',
                             'CLOUDSDK_ACTIVE_CONFIG_NAME=dev',
                             'GOOGLE_APPLICATION_CREDENTIALS=${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE}',
                             'KUBECONFIG=/home/jenkins/kubeconfig-development']) {
                        sh """
                        gcloud config configurations describe ${CLOUDSDK_ACTIVE_CONFIG_NAME} || gcloud config configurations create ${CLOUDSDK_ACTIVE_CONFIG_NAME}
                        gcloud auth activate-service-account --key-file ${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE}
                        gcloud auth configure-docker --quiet
                        docker build -t ${env.DOCKER_PREFIX}/${PROJECT_NAME}:${releaseVersion} .
                        docker push ${env.DOCKER_PREFIX}/${PROJECT_NAME}:${releaseVersion}
                        gcloud container clusters get-credentials ${env.KUBE_DEV_CLUSTER_NAME} --zone ${env.KUBE_DEV_CLUSTER_REGION} --project ${env.GCP_DEV_PROJECT}
                        """
                    }
                }
            }
        }

        // If it's the master branch, then we want to create a release
        stage('Semantic Release') {
            when {
                beforeAgent true
                branch 'master'
            }

            environment {
                SEMANTIC_RELEASE_PATH = tool name: 'semantic-release', type: 'com.cloudbees.jenkins.plugins.customtools.CustomTool'
            }

            steps {
                sshagent (credentials: ['git-ssh-key']) {
                    sh """
                    ${SEMANTIC_RELEASE_PATH}/semantic-release -slug ${env.ORG}/${PROJECT_NAME}
                    """
                }
            }
        }
    }

    post {
        cleanup {
            deleteDir()
            node('master') {
                script {
                    def workspace = pwd()
                    dir("${workspace}@script") {
                        deleteDir()
                    }
                    dir("${workspace}@script@tmp") {
                        deleteDir()
                    }
                }
            }
        }
    }
}
