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

cd ..

# Part 3: Setup OpenProject
git clone https://github.com/opf/openproject-deploy --depth=1 --branch=stable/14 openproject
cd openproject/compose

# Modify OpenProject ports (change 80 to 8082, 443 to 8444, and 8080 to 8083)
sed -i 's/80:80/8082:80/g' docker-compose.yml
sed -i 's/443:443/8444:443/g' docker-compose.yml
sed -i 's/8080:8080/8083:8080/g' docker-compose.yml

docker compose pull
docker compose up -d

cd /root/

# Part 4: Setup listmonk
mkdir listmonk && cd listmonk
bash -c "$(curl -fsSL https://raw.githubusercontent.com/knadh/listmonk/master/install-prod.sh)"
cd ..

# Part 5: Setup plausible
git clone https://github.com/plausible/community-edition plausible
cd plausible

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
docker compose up -d

cd ..

# Part 6: Setup OnlyOffice
echo "Setting up OnlyOffice Document Server"
read -p "Enter your domain for OnlyOffice (e.g., yourdomain.com): " ONLYOFFICE_DOMAIN
read -p "Enter your email for Let's Encrypt (e.g., email@example.com): " ONLYOFFICE_EMAIL
JWT_SECRET=$(openssl rand -base64 32)

# Modify OnlyOffice ports (change 80 to 8084 and 443 to 8445)
sudo docker run -d --name onlyoffice -p 8084:80 -p 8445:443 --restart=always \
    -e LETS_ENCRYPT_DOMAIN=$ONLYOFFICE_DOMAIN \
    -e LETS_ENCRYPT_MAIL=$ONLYOFFICE_EMAIL \
    -e JWT_SECRET=$JWT_SECRET onlyoffice/documentserver

# Part 7: Setup Akaunting
echo "Setting up Akaunting"

git clone https://github.com/akaunting/docker akaunting
cd akaunting

# Copy example env files
cp env/db.env.example env/db.env
cp env/run.env.example env/run.env

# Modify Akaunting ports (change 80 to 8085 and 443 to 8446)
sed -i 's/80:80/8085:80/g' docker-compose.yml
sed -i 's/443:443/8446:443/g' docker-compose.yml

# Edit the env/db.env file
echo "Please configure the db.env file"
nano env/db.env

# Edit the env/run.env file
echo "Please configure the run.env file. Change the ports from 80 to 8045 and 443 to 8446"
nano env/run.env

# Run Akaunting with initial setup
AKAUNTING_SETUP=true docker compose up -d

echo "Please complete the Akaunting setup through the web interface at http://your-docker-host:8085."

read -p "Press enter after completing the Akaunting web setup to continue..."

docker compose down
docker compose up -d

echo "Akaunting setup complete. Never use AKAUNTING_SETUP=true again!"

cd ..

echo "Setup completed successfully!"
