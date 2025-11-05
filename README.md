# 🧠 Ubuntu Autoinstall for Proxmox

**Fully automated Ubuntu 24.04 unattended installation ISO builder and VM deployer for Proxmox VE.**

This project provides a **single Bash script** that builds a complete hands-free Ubuntu Server installation ISO and automatically provisions a new Proxmox VM using it — no user input required.

---

## ⚡ Overview

This script automatically:

✅ Installs required dependencies (`xorriso`, `rsync`, `curl`, etc.)  
✅ Downloads the official Ubuntu 24.04 Live Server ISO  
✅ Injects **cloud-init NoCloud** configuration (`user-data` + `meta-data`)  
✅ Patches GRUB boot entries with the `autoinstall` flag  
✅ Rebuilds a **bootable hybrid BIOS/UEFI ISO**  
✅ Creates and boots a **Proxmox VM** that installs Ubuntu automatically  
✅ Configures users, passwords, SSH access, and ZFS storage automatically  

---

## 🧩 Features

| Feature | Description |
|----------|--------------|
| 🔹 **No human interaction** | Fully automated ISO and VM creation |
| 🔹 **Root & admin users** | Passwords and SSH configured automatically |
| 🔹 **Cloud-init integration** | Uses NoCloud seed for configuration |
| 🔹 **Customizable** | Hostname, username, password, storage, VM ID, etc. |
| 🔹 **ZFS ready** | Creates a ZFS root layout automatically |
| 🔹 **VM auto-start** | Boots and installs Ubuntu in Proxmox instantly |

---

## 🧠 Requirements

- **Proxmox VE 8+**
- Internet access
- Root privileges
- ~10 GB of free disk space in `/var/lib/vz/template/iso`

---

## ⚙️ Installation

### 1️⃣ Save the script

Create a file:

```bash
nano /root/auto-ubuntu-autoinstall.sh
