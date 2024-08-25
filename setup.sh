#!/bin/bash

apt install git -y
apt install curl -y

# Function to install Docker
install_docker() {
  echo "Installing Docker..."

  curl -sSL https://get.docker.com/ | CHANNEL=stable sh
  systemctl enable --now docker

  echo "Docker installed successfully."
}

install_docker

# Part 1: Run the docker command for cosmos-server
docker run -d --network host --privileged --name cosmos-server -h cosmos-server --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /:/mnt/host -v /var/lib/cosmos:/config azukaar/cosmos-server:latest

read -p "Press enter after completing the cosmos web setup (enter the IP address of the server then : and port 80, e.g., 127.0.0.1:80) to continue..."

# Part 2: Setup Mailcow
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

./generate_config.sh

# Ask user if they want to edit mailcow.conf
read -p "Do you want to edit mailcow.conf? (y/n) " EDIT_CONFIG
if [ "$EDIT_CONFIG" == "y" ]; then
  nano mailcow.conf
fi

# Modify Mailcow ports (change 80 to 8081 and 443 to 8443)
sed -i 's/HTTP_PORT=80/HTTP_PORT=8086/g' mailcow.conf
sed -i 's/HTTPS_PORT=443/HTTPS_PORT=8443/g' mailcow.conf

docker compose pull
docker compose up -d

cd /root/

# Part 3: Setup OpenProject

# Prompt for the hostname
read -p "Enter the hostname for OpenProject (e.g., openproject.yourdomain.com): " OPENPROJECT_HOSTNAME

# Generate a random secret key
OPENPROJECT_SECRET_KEY_BASE=$(openssl rand -base64 48)

# Run the OpenProject Docker container with the specified hostname and secret key
docker run -d \
  --name openproject \
  -e OPENPROJECT_SECRET_KEY_BASE=$OPENPROJECT_SECRET_KEY_BASE \
  -e OPENPROJECT_HOST__NAME=$OPENPROJECT_HOSTNAME \
  -e OPENPROJECT_HTTPS=true \
  -e OPENPROJECT_DEFAULT__LANGUAGE=de \
  openproject/openproject:14

cd /root/

#Part 4: Setup listmonk
mkdir listmonk && cd listmonk
bash -c "$(curl -fsSL https://raw.githubusercontent.com/knadh/listmonk/master/install-prod.sh)"
grep 'admin_password = ' config.toml
cd /root/

# Part 5: Setup plausible
git clone https://github.com/plausible/community-edition plausible
cd plausible

# Ask for BASE_URL
read -p "Enter the BASE_URL (important! include https:// ! eg. https://plausible.yourdomain.com) for plausible: " BASE_URL

# Generate secure keys
SECRET_KEY_BASE=$(openssl rand -base64 48)
TOTP_VAULT_KEY=$(openssl rand -base64 32)

# Replace placeholders in plausible-conf.env
sed -i "s|BASE_URL=replace-me|BASE_URL=$BASE_URL|g" plausible-conf.env
sed -i "s|SECRET_KEY_BASE=replace-me|SECRET_KEY_BASE=$SECRET_KEY_BASE|g" plausible-conf.env
sed -i "s|TOTP_VAULT_KEY=replace-me|TOTP_VAULT_KEY=$TOTP_VAULT_KEY|g" plausible-conf.env

# Run docker compose for plausible
docker compose up -d

cd /root/

# Part 6: Setup Akaunting
echo "Setting up Akaunting"

git clone https://github.com/akaunting/docker akaunting
cd akaunting

# Copy example env files
cp env/db.env.example env/db.env
cp env/run.env.example env/run.env

# Modify Akaunting ports (change 80 to 8085 and 443 to 8446)
sed -i 's/8080:80/8085:80/g' docker-compose.yml

# Edit the env/db.env file
echo "Please configure the db.env file"
nano env/db.env

# Edit the env/run.env file
echo "Please configure the run.env file"
nano env/run.env

# Run Akaunting with initial setup
AKAUNTING_SETUP=true docker compose up -d

echo "Please complete the Akaunting setup through the web interface. Add a new URL in cosmos then go to your specified domain!"

read -p "Press enter after completing the Akaunting web setup to continue..."

docker compose down
docker compose up -d

echo "Akaunting setup complete. Never use AKAUNTING_SETUP=true again!"

cd ..

echo "Setup completed successfully!"
