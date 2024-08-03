#!/bin/bash

# Colors for text formatting
RED='\033[0;31m'
NC='\033[0m'      # No Color
YELLOW='\033[33m'
GREEN='\033[32m'

# Function to display error message and exit
error_exit() {
    echo -e "${RED}Error: $1${NC}" 1>&2
    exit 1
}

# Function to display success message
success_msg() {
    echo -e "${GREEN}$1${NC}"
}

# Taking the input from user
echo "${YELLOW}...Enter the Git repository URL:...${NC}"
read GIT_REPO_NAME

echo "${YELLOW}...Enter the Git branch name:....${NC}"
read GIT_BRANCH_NAME

echo "${YELLOW}....Enter the target remote host:....${NC}"
read TARGET_REMOTE_HOST

echo "${YELLOW}...Enter the target user:...${NC}"
read TARGET_REMOTE_USER

echo "${YELLOW}....Enter the target folder location:....${NC}"
read TARGET_FOLDER_LOCATION

echo "${GREEN}...Input taking from user is completed....${NC}"

# Check if any input is empty
if [[ -z $GIT_REPO_NAME || -z $GIT_BRANCH_NAME || -z $TARGET_REMOTE_HOST || -z $TARGET_REMOTE_USER || -z $TARGET_FOLDER_LOCATION ]]; then
    error_exit "One or more input fields are empty. Please provide all the required inputs."
else
    success_msg "All input fields are provided."
fi

# Install Docker
echo "${YELLOW}... Installing Docker....${NC}"
sudo apt update
sudo apt install docker.io -y || error_exit "Failed to install Docker."
success_msg "Docker installed successfully."

# Create Dockerfile
echo "${YELLOW}... Creating Dockerfile....${NC}"
cat <<EOF | sudo tee Dockerfile > /dev/null
FROM jenkins/jenkins:lts
EXPOSE 8080 50000
VOLUME /var/jenkins_home
CMD ["java", "-jar", "/usr/share/jenkins/jenkins.war"]
EOF
success_msg "Dockerfile created successfully."
sleep 30

# Build Jenkins image
echo "${YELLOW}... Building Jenkins image....${NC}"
sudo docker build -t my-custom-jenkins . || error_exit "Failed to build Jenkins image."
success_msg "Jenkins image built successfully."

# Run Jenkins container
echo "${YELLOW}... Running Jenkins container....${NC}"
sudo docker run -d -p 8080:8080 -p 50000:50000 -v /home/ubuntu/jenkins_data:/var/jenkins_home --name jenkins --restart always jenkins/jenkins:lts || error_exit "Failed to run Jenkins container."
sudo chown -R 1000:1000 /home/ubuntu/jenkins_data
sudo chmod -R 777 /home/ubuntu/jenkins_data
#wait_for_container "jenkins" || error_exit "Failed to start Jenkins container."
success_msg "Jenkins container is up and running."

sleep 10

# Find the container ID
echo "${YELLOW}... Obtaining container IP address....${NC}"
CONTAINER_ID=$(sudo docker ps -aqf "name=jenkins")

# Display the logs of the container
echo "${YELLOW}... Displaying container logs....${NC}"
logs=$(sudo docker logs "$CONTAINER_ID")
echo "$logs"
echo "Setup-jenkins: Create your admin using jenkins webUI. Jenkins is available in port 8080 of this instance public-ip"

sleep 120

echo "${YELLOW}...Enter Jenkins Username...${NC}"
read user_name
echo "${YELLOW}...Enter Jenkins password:...${NC}"
read pass_word

# Install wget and nano inside the container
echo "${YELLOW}... Installing wget and nano inside the container....${NC}"
sudo docker exec -u root jenkins apt-get update
sudo docker exec -u root jenkins apt-get install -y wget nano
success_msg "wget and nano installed successfully inside the container."

# Restart Jenkins container to apply plugin changes
echo "${YELLOW}... Restarting Jenkins container to apply plugin changes....${NC}"
sudo docker restart jenkins || error_exit "Failed to restart Jenkins container."
success_msg "Jenkins container restarted successfully."
# Wait for Jenkins container to restart
echo "${YELLOW}... Waiting for Jenkins container to restart....${NC}"
sleep 30


# Get container IP address
echo "${YELLOW}... Obtaining container IP address....${NC}"
CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

# Download Jenkins CLI JAR file
echo "${YELLOW}... Downloading the Jenkins CLI jar file...${NC}"
sudo docker exec -u root jenkins wget "http://$CONTAINER_IP:8080/jnlpJars/jenkins-cli.jar"

#make sure that jenkins is up and running

sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth $user_name:$pass_word install-plugin gitlab-plugin || error_exit "Failed to install GitLab plugin."
sudo docker exec -u root jenkins java -jar /jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth $user_name:$pass_word install-plugin credentials
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth $user_name:$pass_word install-plugin gitlab-api
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth $user_name:$pass_word install-plugin gitlab-oauth
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth $user_name:$pass_word install-plugin generic-webhook-trigger
sudo docker restart jenkins


# Execute commands inside the Jenkins container
echo "The below showing the public-key. Update the public key in the gitlab ssh settings. also give the url and username, password in the gitlab integration"
#sudo docker exec -u root jenkins bash -c 'ssh-keygen -t rsa -b 4096 && cat ~/.ssh/id_rsa.pub'
sudo docker exec jenkins mkdir /var/jenkins_home/.ssh
sudo docker exec jenkins chmod 700 /var/jenkins_home/.ssh
sudo docker exec jenkins ssh-keygen -t rsa -b 4096 -f /var/jenkins_home/.ssh/id_rsa -N ""
sudo docker exec jenkins cat /var/jenkins_home/.ssh/id_rsa.pub
sleep 120


# Taking the input from user and storing in a file
echo "${YELLOW}Enter the public key of the target machine below:${NC}"
echo "${YELLOW}Press Ctrl+D when finished:${NC}"
cat > ec2_pemkey.pem || error_exit "Failed to store public key in ec2_pemkey.pem file."
success_msg "Public key stored successfully in ec2_pemkey.pem file."
sleep 60
# Change permissions of the file
sudo chmod 600 ec2_pemkey.pem || error_exit "Failed to change permissions of ec2_pemkey.pem file."
success_msg "Permissions changed successfully for ec2_pemkey.pem file."
sleep 10
# Write the public key directly to the Docker volume
echo "${YELLOW}... Writing public key to Docker volume....${NC}"
sudo docker cp ec2_pemkey.pem jenkins:/var/jenkins_home/ || error_exit "Failed to write public key to Docker volume"
success_msg "Public key written successfully to /var/jenkins_home/ec2_pemkey.pem inside the Jenkins container."
sleep 10

#Define the job_config.xml file
cat <<EOF | sudo tee job_config.xml > /dev/null
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.42">
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig plugin="pipeline-model-definition@1.10.2">
      <dockerLabel></dockerLabel>
      <registry plugin="docker-commons@1.17"/>
      <registryCredentialId></registryCredentialId>
    </org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.90">
    <script>
pipeline {
    agent any
    environment {
        GIT_SSH_COMMAND = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Code checkout from the repository'
                sh 'git clone -b dev git@gitlab.com:practice-group9221502/jenkins-project.git'
            }
        }
        stage('Transfer HTML File') {
            steps {
                script {
                    // List files to verify the context
                    sh 'ls -a'
                    // Find HTML file
                    def htmlFile = sh(returnStdout: true, script: 'find /var/jenkins_home/workspace/mn-serviceproviders-website -name "*.html"').trim() 
                    // Transfer the HTML file to another machine via SSH
                    sh "scp -o StrictHostKeyChecking=no -i /var/jenkins_home/ec2_pemkey.pem \"\$htmlFile\" ubuntu@$TARGET_REMOTE_HOST:/home/ubuntu/"

                }
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
  <!-- GitLab configuration -->
  <scm class="hudson.plugins.git.GitSCM" plugin="git@4.12.0">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>https://gitlab.com</url> <!-- GitLab host URL -->
        <credentialsId>glpat-dYoPmMpwhPRQSjkhB3zs</credentialsId> <!-- Credentials ID for GitLab API token -->
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <!-- Other Git SCM settings -->
  </scm>
</flow-definition>
EOF
success_msg "job_config.xml created successfully."


sleep 30

# Copy job_config.xml to Jenkins container
echo "${YELLOW}... Copying job_config.xml to Jenkins container....${NC}"
sudo docker cp job_config.xml jenkins:/var/jenkins_home/ || { echo -e "${RED}Failed to copy job_config.xml to Jenkins container.${NC}"; exit 1; }

# Restart Jenkins container
echo "${YELLOW}... Restarting Jenkins container....${NC}"
sudo docker restart jenkins || { echo -e "${RED}Failed to restart Jenkins container.${NC}"; exit 1; }
success_msg "Jenkins container restarted successfully."

sleep 30

# Create job
echo "${YELLOW}... Creating job mn-serviceproviders-website....${NC}"
sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth $user_name:$pass_word -s http://$CONTAINER_IP:8080/ create-job mn-serviceproviders-website < var/jenkins_home/job_config.xml" || { echo -e "${RED}Failed to create job.${NC}"; exit 1; }
sleep 30

# List jobs
echo "${YELLOW}... Listing jobs....${NC}"
sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth "$user_name":"$pass_word" -s http://$CONTAINER_IP:8080/ list-jobs" || { echo -e "${RED}Failed to list jobs.${NC}"; exit 1; }

# Build the job
echo "${YELLOW}... Building job mn-serviceproviders-website....${NC}"
sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth "$user_name":"$pass_word" -s http://$CONTAINER_IP:8080/ build mn-serviceproviders-website" || { echo -e "${RED}Failed to build job.${NC}"; exit 1; }

success_msg "Job created and built successfully."


