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

echo "${YELLOW}....Enter the personal_access_token of gitlab....${NC}"
read Personal_access_token

# Ask for Jenkins storage location or use default
echo "${YELLOW}...Jenkins storage location [default: /home/ubuntu/jenkins_data]:...${NC}"
read Jenkins_storage_location

# Check if Jenkins storage location is empty
if [[ -z $Jenkins_storage_location ]]; then
    Jenkins_storage_location="/home/ubuntu/jenkins_data"  # Set default location
fi

# Check if the specified location exists or create it
if [ ! -d "$Jenkins_storage_location" ]; then
    echo "${YELLOW}...Specified Jenkins storage location doesn't exist. Creating it...${NC}"
    sudo mkdir -p "$Jenkins_storage_location" || error_exit "Failed to create Jenkins storage location."
    sudo chown -R "$(whoami)": "$(Jenkins_storage_location)" || error_exit "Failed to set ownership for Jenkins storage location."
    sudo chmod -R 777 "$Jenkins_storage_location" || error_exit "Failed to set permissions for Jenkins storage location."
    success_msg "Jenkins storage location created successfully."
fi

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
sudo docker run -d -p 8080:8080 -p 50000:50000 -v "$Jenkins_storage_location:/var/jenkins_home" --name jenkins --restart always jenkins/jenkins:lts || error_exit "Failed to run Jenkins container."
sudo chown -R 1000:1000 "$Jenkins_storage_location"
sudo chmod -R 777 "$Jenkins_storage_location"
success_msg "Jenkins container is up and running."

sleep 10


# Find the container ID
echo "${YELLOW}... Obtaining container IP address....${NC}"
CONTAINER_ID=$(sudo docker ps -aqf "name=jenkins")

# Get initial admin password
echo "${YELLOW}... Getting initial admin password....${NC}"
INITIAL_ADMIN_PASSWORD=$(sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)

# Display the initial admin password
echo "Initial Admin Password: $INITIAL_ADMIN_PASSWORD"

sleep 10

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
sleep 60


# Get container IP address
echo "${YELLOW}... Obtaining container IP address....${NC}"
CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

# Download Jenkins CLI JAR file
echo "${YELLOW}... Downloading the Jenkins CLI jar file...${NC}"
sudo docker exec -u root jenkins wget "http://$CONTAINER_IP:8080/jnlpJars/jenkins-cli.jar"

#make sure that jenkins is up and running

sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth admin:$INITIAL_ADMIN_PASSWORD install-plugin gitlab-plugin || error_exit "Failed to install GitLab plugin."
sudo docker exec -u root jenkins java -jar /jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth admin:$INITIAL_ADMIN_PASSWORD install-plugin credentials
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth admin:$INITIAL_ADMIN_PASSWORD install-plugin gitlab-api
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth admin:$INITIAL_ADMIN_PASSWORD install-plugin gitlab-oauth
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -s "http://$CONTAINER_IP:8080/" -auth admin:$INITIAL_ADMIN_PASSWORD install-plugin generic-webhook-trigger
sudo docker restart jenkins


# Execute commands inside the Jenkins container
echo "The below showing the public-key. Update the public key in the GitLab SSH settings. Also give the URL and username, password in the GitLab integration"
# Generate SSH keys inside the container
sudo docker exec jenkins bash -c 'mkdir /var/jenkins_home/.ssh && chmod 700 /var/jenkins_home/.ssh && ssh-keygen -t rsa -b 4096 -f /var/jenkins_home/.ssh/id_rsa -N ""'

# Retrieve the public key and store it in a variable
public_key=$(sudo docker exec jenkins cat /var/jenkins_home/.ssh/id_rsa.pub)

# Display the public key
echo "Public key: $public_key"
sleep 30

# Using cURL to add the SSH key to GitLab
curl --request POST \
--header "PRIVATE-TOKEN: $Personal_access_token" \
--header "Content-Type: application/json" \
--data "{
  \"title\": \"My SSH Key\",
  \"key\": \"$public_key\",
  \"can_push\": true
}" \
"https://gitlab.com/api/v4/user/keys"

echo "------------------------------------------------------------------------------------"

sleep 20 
#setuping the jenkins-service in gitlab

echo "${YELLOW}....Enter the JENKINS_URL....${NC}"
read JENKINS_URL

echo "${YELLOW}....Enter the PROJECT_NAME....${NC}"
read PROJECT_NAME

echo "${YELLOW}....Enter the JENKINS_USERNAME....${NC}"
read JENKINS_USERNAME

echo "${YELLOW}....Enter the JENKINS_PASSWORD....${NC}"
read JENKINS_PASSWORD

curl --request POST \
--header "PRIVATE-TOKEN: $YOUR_PRIVATE_TOKEN" \
--header "Content-Type: application/json" \
--data "{
  \"jenkins_url\": \"$JENKINS_URL\",
  \"project_name\": \"$PROJECT_NAME\",
  \"username\": \"$JENKINS_USERNAME\",
  \"password\": \"$JENKINS_PASSWORD\"
}" \
"https://gitlab.com/api/v4/projects/PROJECT_ID/services/jenkins"

sleep 20

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
                    echo "HTML file path: $htmlFile"  // Debug output to check the file path
                    // Transfer the HTML file to another machine via SSH
                    sh "scp -o StrictHostKeyChecking=no -i /var/jenkins_home/ec2_pemkey.pem \"$htmlFile\" ubuntu@$TARGET_REMOTE_HOST:/home/ubuntu/"
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
        <credentialsId>$Personal_access_token</credentialsId> <!-- Credentials ID for GitLab API token -->
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
sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth admin:$INITIAL_ADMIN_PASSWORD -s http://$CONTAINER_IP:8080/ create-job mn-serviceproviders-website < var/jenkins_home/job_config.xml" || { echo -e "${RED}Failed to create job.${NC}"; exit 1; }
sleep 30

# List jobs
echo "${YELLOW}... Listing jobs....${NC}"
sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth admin:"$INITIAL_ADMIN_PASSWORD" -s http://$CONTAINER_IP:8080/ list-jobs" || { echo -e "${RED}Failed to list jobs.${NC}"; exit 1; }

# Build the job
echo "${YELLOW}... Building job mn-serviceproviders-website....${NC}"
sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth admin:"$INITIAL_ADMIN_PASSWORD" -s http://$CONTAINER_IP:8080/ build mn-serviceproviders-website" || { echo -e "${RED}Failed to build job.${NC}"; exit 1; }

success_msg "Job created and built successfully."


