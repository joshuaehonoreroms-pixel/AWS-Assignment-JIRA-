#!/bin/bash
# EC2 Bootstrap Script — Java Spring Microservices
# Runs automatically on first boot via EC2 user-data
# Installs Docker, clones the repo, and starts all services

set -e

echo "========================================="
echo " Starting EC2 Bootstrap"
echo "========================================="

# Update system packages
yum update -y

# Install Docker
yum install -y docker git
systemctl start docker
systemctl enable docker

# Add ec2-user to the docker group so we can run docker without sudo
usermod -aG docker ec2-user

# Install Docker Compose v2
DOCKER_COMPOSE_VERSION="v2.27.0"
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Clone the repo (public GitHub repo)
REPO_URL="https://github.com/joshuaehonoreroms-pixel/AWS-Assignment-JIRA-.git"
APP_DIR="/home/ec2-user/app"

if [ -d "$APP_DIR" ]; then
  echo "Directory already exists, pulling latest..."
  cd "$APP_DIR"
  git pull
else
  echo "Cloning repo..."
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

# Give ec2-user ownership
chown -R ec2-user:ec2-user "$APP_DIR"

# Start all services in detached mode
# Note: First boot will take 5-10 mins to build all Java images
echo "Starting Docker Compose (build + up)..."
docker-compose up --build -d

echo "========================================="
echo " Bootstrap complete!"
echo " Services are building in the background."
echo " Run: docker-compose logs -f"
echo " to watch progress."
echo "========================================="
