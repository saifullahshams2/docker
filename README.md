# 🚀 Automated Docker & Microservices Server Stack

An automated, resilient, and interactive Bash deployment suite designed to transform any fresh Ubuntu/Debian server into a secure, production-grade containerized environment in minutes.

Automatically provisions **Docker Engine & Docker Compose**, establishes an isolated bridge network (`caddynet`), interactively configures automatic HTTPS reverse proxying with **Caddy**, and deploys self-hosted services: **Portainer CE**, **n8n**, and **WG-Easy (WireGuard VPN)**.

---

## ⚡ Quick Start

### Prerequisites
- **Operating System**: Ubuntu 20.04 / 22.04 / 24.04 LTS or Debian 11 / 12.
- **User Account**: Run as a regular user with `sudo` group permissions (*do not run directly as root*).
- **DNS (A/AAAA Records)**: Point your domain/subdomains to your server's public IP before setup if configuring SSL reverse proxying.
- **Firewall Ports**:
  - `80/tcp` & `443/tcp` / `443/udp` (HTTP/HTTPS & HTTP/3 for Caddy)
  - `51820/udp` (WireGuard VPN tunnel traffic, if using WG-Easy)

---

### One-Line Automated Installation

Run the following command in your terminal:

```bash
(command -v git >/dev/null 2>&1 || (sudo apt-get update -y && sudo apt-get install -y git)) && (test -d docker || git clone https://github.com/saifullahshams2/docker.git) && cd docker && bash setup.sh
```

> **Note for Root-only VPS users:**
> If your VPS provider only gave you `root` access, create and switch to a sudo-enabled user first:
> ```bash
> adduser deploy
> usermod -aG sudo deploy
> su - deploy
> ```

---

## 📦 Service Catalog

| Service | Role | Container Name | Internal Port | Host Binding | Public Exposure |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **[Caddy](https://caddyserver.com/)** | Edge Reverse Proxy & Automatic SSL | `caddy` | `80`, `443` | `0.0.0.0:80`<br>`0.0.0.0:443` | Auto HTTPS via Let's Encrypt / ZeroSSL |
| **[Portainer CE](https://www.portainer.io/)** | Docker Container Management UI | `portainer` | `9000` | `127.0.0.1:9000` | `https://portainer.yourdomain.com` |
| **[n8n](https://n8n.io/)** | Low-Code Workflow Automation | `n8n` | `5678` | `127.0.0.1:5678` | `https://n8n.yourdomain.com` |
| **[WG-Easy](https://github.com/wg-easy/wg-easy)** | WireGuard VPN + Management Web UI | `wg-easy` | `51820/udp`<br>`51821/tcp` | `0.0.0.0:51820/udp`<br>`127.0.0.1:51821` | `https://vpn.yourdomain.com` |

---

## 🏗️ Architecture & Network Flow

```text
                                  [ Internet / Clients ]
                                             |
                                    +--------+--------+
                                    | Ports 80 & 443  |
                                    v                 v
                   +----------------------------------------------------+
                   |               Caddy Reverse Proxy                  |
                   |             (Automatic SSL via ACME)               |
                   +------------------------+---------------------------+
                                            |
                         [ External Docker Network: 'caddynet' ]
                                            |
               +----------------------------+----------------------------+
               |                            |                            |
               v                            v                            v
     +--------------------+      +--------------------+      +--------------------+
     |   Portainer CE     |      |       n8n          |      |      WG-Easy       |
     |   (portainer:9000) |      |    (n8n:5678)      |      |  (wg-easy:51821)   |
     +--------------------+      +--------------------+      +---------+----------+
                                                                       | (Port 51820/udp)
                                                                       v
                                                              [ WireGuard Clients ]
```

### Design Principles:
1. **Loopback Port Binding**: Application ports (`9000`, `5678`, `51821`) bind to `127.0.0.1` (localhost), routing external web traffic through Caddy reverse proxy.
2. **Container Isolation**: Applications run in individual Docker Compose stacks with dedicated bridge networks (`n8nnet`, `wg`, `portainer_network`) while connected to `caddynet` for reverse proxying.
3. **Dedicated User Context**: n8n runs under `user: "1000:1000"` with matching file permissions on `./data`.
4. **Session Keepalive**: `setup.sh` maintains a background keep-alive process during setup that automatically terminates on exit.
5. **Apt Lock Resilience**: Automatically waits for background package update locks to release before proceeding.

---

## 🛠️ Interactive Installation Walkthrough

When `setup.sh` is executed:

1. **Permission Validation**: Confirms non-root execution and verifies administrative group membership.
2. **Environment & Logging**: Directs all terminal logs to `setup.log` while displaying real-time output.
3. **Docker Engine Installation**:
   - Detects existing Docker instances.
   - If missing, registers Docker's official GPG key and repository and installs `docker-ce`, `containerd.io`, and `docker-compose-plugin`.
   - Adds the current user to the `docker` group.
4. **Shared Network**: Creates the external Docker network `caddynet`.
5. **Interactive Service Configuration**:
   - **Caddy**: Choose whether to deploy Caddy as your reverse proxy.
   - **Portainer**: Prompts for custom domain name (e.g., `portainer.yourdomain.com`).
   - **n8n**: Prompts for domain name and timezone (defaults to `Asia/Riyadh`). Automatically configures webhook URLs and sets permissions on `./n8n/data`.
   - **WG-Easy**: Prompts for custom domain name for the WireGuard dashboard.
6. **Orchestration**: Launches selected containers in detached mode (`docker compose up -d`).
7. **Summary & Verification**: Prints access URLs and provides an option to reboot the server.

---

## 📁 Repository Structure

```text
.
├── setup.sh                 # Master interactive installation & provisioning script
├── README.md                # Project documentation and operational guide
├── caddy/
│   ├── compose.yaml         # Caddy Docker Compose configuration (Ports 80/443)
│   └── Caddyfile            # Caddy reverse proxy routing rules & SSL configs
├── n8n/
│   └── compose.yaml         # n8n Docker Compose configuration (User 1000:1000)
├── portainer/
│   └── compose.yaml         # Portainer CE Docker Compose configuration
└── wgeasy/
    └── compose.yaml         # WG-Easy WireGuard VPN Docker Compose configuration
```

---

## 🔑 Portainer Initial Setup & Token

- **Get Setup Token**: During the initial Portainer setup, a security setup token is required. Run the following command to view your token from the logs:
  ```bash
  sudo docker logs portainer
  ```
- **Setup Timeout**: If you exceed the initial setup time limit and are locked out of creating the admin user, restart the Portainer container to reset the setup window:
  ```bash
  sudo docker restart portainer
  ```

---

## 📄 License

This project was completely created by AI and is distributed under the [MIT License](LICENSE).

