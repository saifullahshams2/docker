# 🚀 Docker & Services Automated Server Stack

An interactive, automated bash deployment suite to turn a fresh Ubuntu/Debian VPS into a production-ready containerized environment in minutes.

Automatically installs **Docker Engine & Docker Compose**, creates a unified bridge network (`caddynet`), interactively configures SSL reverse-proxying with **Caddy**, and provisions self-hosted tools: **Portainer**, **n8n**, and **WG-Easy (WireGuard VPN)**.

---

## ⚡ Quick Start (One-Command Installer)

Run this single command on your Ubuntu/Debian server as `root` or any user with `sudo` privileges:

```bash
curl -fsSL https://raw.githubusercontent.com/saifullahshams2/docker/main/setup.sh | bash
```

> **Alternative using wget:**
> ```bash
> wget -qO- https://raw.githubusercontent.com/saifullahshams2/docker/main/setup.sh | bash
> ```

> **Alternative via Git Clone:**
> ```bash
> git clone https://github.com/saifullahshams2/docker.git
> cd docker
> bash setup.sh
> ```

---

## 📦 What's Included?

| Service | Category | Container Name | Internal Port | Local Binding | Public Exposure (via Caddy) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **[Caddy](https://caddyserver.com/)** | Reverse Proxy & SSL | `caddy` | `80`, `443` | `0.0.0.0:80`, `0.0.0.0:443` | Automatic HTTPS & ACME certs |
| **[Portainer CE](https://www.portainer.io/)** | Container Management UI | `portainer` | `9000` | `127.0.0.1:9000` | `https://portainer.yourdomain.com` |
| **[n8n](https://n8n.io/)** | Workflow Automation | `n8n` | `5678` | `127.0.0.1:5678` | `https://n8n.yourdomain.com` |
| **[WG-Easy](https://github.com/wg-easy/wg-easy)** | WireGuard VPN + Web UI | `wg-easy` | `51820/udp`, `51821` | `0.0.0.0:51820/udp`, `127.0.0.1:51821` | `https://vpn.yourdomain.com` |

---

## 🏗️ Architecture & Network Flow

```
                                  [ Internet / Users ]
                                           |
                                  +--------+--------+
                                  | Ports 80 & 443  |
                                  v                 v
                 +----------------------------------------------------+
                 |               Caddy Reverse Proxy                  |
                 |             (Automatic SSL via ACME)               |
                 +------------------------+---------------------------+
                                          |
                        [ Shared Network: 'caddynet' ]
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

* **Zero Direct Public Exposure**: Back-end service ports (`9000`, `5678`, `51821`) are bound to `127.0.0.1` on the host, preventing bypass of reverse-proxy authentication and HTTPS.
* **Service Discovery**: Containers communicate internally across the `caddynet` bridge by container name.

---

## 📋 Prerequisites & DNS Configuration

1. **Operating System**: Ubuntu 20.04/22.04/24.04 LTS or Debian 11/12.
2. **User Privileges**: `root` or a user with `sudo` permissions (the script auto-elevates when required).
3. **Firewall Ports**: Ensure the following incoming ports are allowed in your cloud provider / VPS firewall:
   - `80/tcp` (HTTP - required for ACME certificate verification)
   - `443/tcp` & `443/udp` (HTTPS & HTTP/3)
   - `51820/udp` (WireGuard VPN tunnel traffic, if using WG-Easy)
4. **DNS Records (A/AAAA)**:
   Point your domain/subdomains to your server's public IP before running the installer so Caddy can automatically issue TLS certificates:
   - `portainer.yourdomain.com` ➔ `YOUR_SERVER_IP`
   - `n8n.yourdomain.com` ➔ `YOUR_SERVER_IP`
   - `vpn.yourdomain.com` ➔ `YOUR_SERVER_IP`

---

## 🛠️ Step-by-Step Installation Flow

When you run `setup.sh`, it executes the following 6 stages:

1. **Privilege & Environment Check**: Confirms superuser privileges and attaches standard terminal I/O for interactive menus.
2. **Docker Engine & Plugin Setup**: Checks if Docker is installed; if missing, installs Docker Engine and `docker-compose-plugin` using Docker's official repositories.
3. **Network Creation**: Creates the external Docker bridge network `caddynet`.
4. **Interactive Prompts**:
   - Asks which services you want to deploy (`y/n`).
   - Prompts for your public domains for Caddy reverse-proxying.
   - Prompts for your preferred timezone for n8n (defaults to `Asia/Riyadh`).
   - Generates updated `compose.yaml` files and `caddy/Caddyfile`.
5. **Container Orchestration**: Launches each chosen service cleanly in the background (`docker compose up -d`).
6. **System Upgrade & Summary**: Runs `apt-get upgrade -y` to keep OS packages secure, then outputs a table with all live URLs and endpoints.

---

## 📁 Repository Structure

```text
.
├── setup.sh                 # Interactive master installation & provisioning script
├── README.md                # Project documentation
├── caddy/
│   ├── compose.yaml         # Caddy Docker Compose configuration
│   └── Caddyfile            # Caddy reverse proxy rules & SSL definitions
├── n8n/
│   └── compose.yaml         # n8n workflow engine Docker Compose configuration
├── portainer/
│   └── compose.yaml         # Portainer CE Docker Compose configuration
└── wgeasy/
    └── compose.yaml         # WG-Easy WireGuard Docker Compose configuration
```

---

## 🔧 Managing Your Services

All services are organized in independent modular directories. You can manage any individual service using standard `docker compose` commands:

### Restart a Specific Service
```bash
cd /opt/docker/n8n      # Or your local cloned repo directory
docker compose restart
```

### View Live Logs
```bash
cd /opt/docker/caddy
docker compose logs -f
```

### Update a Service Image
```bash
cd /opt/docker/portainer
docker compose pull
docker compose up -d
```

### Reload Caddy Configuration Without Downtime
```bash
docker exec -w /etc/caddy caddy caddy reload
```

---

## 🔒 Security Best Practices

- **WireGuard Web Dashboard**: Remember to set an administrative password for WG-Easy by adding `PASSWORD_HASH` or `PASSWORD` in `wgeasy/compose.yaml`.
- **WireGuard Host IP**: For external VPN connections to connect properly, set `- WG_HOST=YOUR_PUBLIC_SERVER_IP` under the `environment` section of `wgeasy/compose.yaml`.
- **First Login to Portainer**: Open the Portainer web UI immediately after deployment to create the initial admin user before the setup timeout expires.

---

## 📄 License

Distributed under the MIT License.
