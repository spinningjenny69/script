#!/bin/bash

# Function to install Docker
install_docker() {
  echo "Installing Docker..."

  curl -sSL https://get.docker.com/ | CHANNEL=stable sh
# After the installation process is finished, you may need to enable the service and make sure it is started (e.g. CentOS 7)
  systemctl enable --now docker

  echo "Docker installed successfully."
}

# Function to install the latest version of Docker Compose
install_docker_compose() {
  echo "Installing the latest version of Docker Compose..."

  # Fetch the latest Docker Compose version
  LATEST=$(curl -Ls -w %{url_effective} -o /dev/null https://github.com/docker/compose/releases/latest)
  LATEST=${LATEST##*/}
  
  # Download and install Docker Compose
  sudo curl -L https://github.com/docker/compose/releases/download/$LATEST/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose

  echo "Docker Compose installed successfully."
}

# Function to check if a command exists and install it if not
check_command() {
  COMMAND=$1
  INSTALL_FUNC=$2
  if ! command -v $COMMAND &> /dev/null; then
    echo "$COMMAND is not installed. Installing..."
    $INSTALL_FUNC
  else
    echo "$COMMAND is already installed."
  fi
}

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
cd openproject/compose

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

sudo docker run -d -p 81:81 -p 444:444 --restart=always \
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
