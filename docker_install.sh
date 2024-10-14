#!/bin/bash
# Install Portainer for Docker Portainer will be in Port :9000
docker volume create portainer_data
docker run -d -p 9000:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
#
# Install Caddy Docker
cd ~
mkdir caddy
cd caddy
touch Caddyfile
docker network create -d bridge caddy-net
docker run --net caddy-net --name caddy --restart always -p 80:80 -p 443:443 -p 443:443/udp -v $PWD/Caddyfile:/etc/caddy/Caddyfile -v $PWD/site:/srv -v $PWD/caddy_data:/data -v $PWD/caddy_config:/config caddy:latest
docker network connect caddy-net portainer
