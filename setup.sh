#!/bin/bash

# Function to check and install required packages
check_and_install() {
  PACKAGE=$1
  if ! command -v $PACKAGE &> /dev/null; then
    echo "$PACKAGE is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y $PACKAGE
  else
    echo "$PACKAGE is already installed."
  fi
}

# Check and install docker, docker-compose, curl, openssl, and git
check_and_install docker
check_and_install docker-compose
check_and_install curl
check_and_install openssl
check_and_install git

# Part 1: Setup listmonk
mkdir listmonk && cd listmonk
bash -c "$(curl -fsSL https://raw.githubusercontent.com/knadh/listmonk/master/install-prod.sh)"
cd ..

# Part 2: Setup plausible
git clone https://github.com/plausible/community-edition hosting
cd hosting

# Ask for BASE_URL
read -p "Enter the BASE_URL for plausible: " BASE_URL

# Generate secure keys
SECRET_KEY_BASE=$(openssl rand -base64 48)
TOTP_VAULT_KEY=$(openssl rand -base64 32)

# Replace placeholders in plausible-conf.env
sed -i "s|BASE_URL=replace-me|BASE_URL=$BASE_URL|g" plausible-conf.env
sed -i "s|SECRET_KEY_BASE=replace-me|SECRET_KEY_BASE=$SECRET_KEY_BASE|g" plausible-conf.env
sed -i "s|TOTP_VAULT_KEY=replace-me|TOTP_VAULT_KEY=$TOTP_VAULT_KEY|g" plausible-conf.env

# Run docker compose for plausible
docker-compose up -d

# Go back to the root directory
cd ..

# Part 3: Setup OpenProject
git clone https://github.com/opf/openproject-deploy --depth=1 --branch=stable/14 openproject
cd openproject

# Pull the OpenProject Docker image and start containers
docker-compose pull
docker-compose up -d

# Go back to the root directory
cd ..

# Part 4: Setup Mailcow
su -c 'bash -c "
umask 0022
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

# Initialize Mailcow and generate config
./generate_config.sh

# Ask user if they want to edit mailcow.conf
read -p \"Do you want to edit mailcow.conf? (y/n) \" EDIT_CONFIG
if [ \"\$EDIT_CONFIG\" == \"y\" ]; then
  nano mailcow.conf
fi

# Pull and start mailcow services
docker-compose pull
docker-compose up -d
"'

# Part 5: Setup OnlyOffice
echo "Setting up OnlyOffice Document Server"
read -p "Enter your domain for OnlyOffice (e.g., yourdomain.com): " ONLYOFFICE_DOMAIN
read -p "Enter your email for Let's Encrypt (e.g., email@example.com): " ONLYOFFICE_EMAIL
JWT_SECRET=$(openssl rand -base64 32)

sudo docker run -i -t -d -p 80:80 -p 443:443 --restart=always \
    -e LETS_ENCRYPT_DOMAIN=$ONLYOFFICE_DOMAIN \
    -e LETS_ENCRYPT_MAIL=$ONLYOFFICE_EMAIL \
    -e JWT_SECRET=$JWT_SECRET onlyoffice/documentserver

# Part 6: Setup Akaunting
echo "Setting up Akaunting"

# Clone the Akaunting repository
git clone https://github.com/akaunting/docker akaunting
cd akaunting

# Copy example env files
cp env/db.env.example env/db.env
cp env/run.env.example env/run.env

# Edit the env/db.env file
echo "Please configure the db.env file"
nano env/db.env

# Edit the env/run.env file
echo "Please configure the run.env file"
nano env/run.env

# Run Akaunting with initial setup
AKAUNTING_SETUP=true docker-compose up -d

echo "Please complete the Akaunting setup through the web interface at http://your-docker-host:8080."

# Once setup is complete, bring containers down and restart without AKAUNTING_SETUP
read -p "Press enter after completing the Akaunting web setup to continue..."

docker-compose down
docker-compose up -d

echo "Akaunting setup complete. Never use AKAUNTING_SETUP=true again!"

# Go back to the root directory
cd ..

# Part 7: Run the final docker command for cosmos-server
docker run -d --network host --privileged --name cosmos-server -h cosmos-server --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /:/mnt/host -v /var/lib/cosmos:/config azukaar/cosmos-server:latest

echo "Setup completed successfully!"
