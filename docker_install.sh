#!/bin/bash
# Update & Upgrade
sudo apt update && sudo apt upgrade -y
# Install Docker
sudo apt-get update
sudo apt install apt-transport-https ca-certificates curl software-properties-common
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo systemctl start docker
sudo systemctl enable docker
# Install Portainer for Docker Portainer will be in Port :9000
docker volume create portainer_data
docker run -d -p 9000:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
# Install Caddy Docker
docker network create -d bridge caddy-net
docker volume create caddy_data
docker volume create caddy_config
docker run --net caddy-net --name caddy --restart always -p 80:80 -p 443:443 -p 443:443/udp -v $PWD/Caddyfile:/etc/caddy/Caddyfile -v $PWD/site:/srv -v $PWD/caddy_data:/data -v $PWD/caddy_config:/config caddy:latest
