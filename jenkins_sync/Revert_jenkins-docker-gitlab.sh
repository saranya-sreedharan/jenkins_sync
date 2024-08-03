#!/bin/bash

# Stop Jenkins container
echo "${YELLOW}... Stopping Jenkins container....${NC}"
sudo docker stop jenkins || { echo -e "${RED}Failed to stop Jenkins container.${NC}"; exit 1; }
success_msg "Jenkins container stopped successfully."

# Remove Jenkins container
echo "${YELLOW}... Removing Jenkins container....${NC}"
sudo docker rm jenkins || { echo -e "${RED}Failed to remove Jenkins container.${NC}"; exit 1; }
success_msg "Jenkins container removed successfully."

# Remove Jenkins image
echo "${YELLOW}... Removing Jenkins image....${NC}"
sudo docker rmi my-custom-jenkins || { echo -e "${RED}Failed to remove Jenkins image.${NC}"; exit 1; }
success_msg "Jenkins image removed successfully."

# Remove Dockerfile
echo "${YELLOW}... Removing Dockerfile....${NC}"
sudo rm Dockerfile || { echo -e "${RED}Failed to remove Dockerfile.${NC}"; exit 1; }
success_msg "Dockerfile removed successfully."

# Uninstall Docker
echo "${YELLOW}... Uninstalling Docker....${NC}"
sudo apt remove --purge docker.io -y || { echo -e "${RED}Failed to uninstall Docker.${NC}"; exit 1; }
sudo apt autoremove -y || { echo -e "${RED}Failed to remove Docker dependencies.${NC}"; exit 1; }
success_msg "Docker uninstalled successfully."

# Remove job_config.xml file
echo "${YELLOW}... Removing job_config.xml file....${NC}"
sudo rm job_config.xml || { echo -e "${RED}Failed to remove job_config.xml file.${NC}"; exit 1; }
success_msg "job_config.xml file removed successfully."
