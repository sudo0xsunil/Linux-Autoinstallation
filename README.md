# 🚀 Linux Autoinstall for Proxmox

### Fully Automated Ubuntu 24.04 LTS Unattended Installer  
**Built and maintained by [Sunil Kumar (@sudo0xsunil)](https://github.com/sudo0xsunil)**

---

## 🧠 Overview

This project provides a **single Bash script** that automates the entire process of creating and deploying an **unattended Ubuntu Server installation** in **Proxmox VE**.

It automatically:
- Installs all required dependencies  
- Downloads the latest official Ubuntu ISO  
- Injects your **cloud-init (NoCloud)** autoinstall configuration  
- Patches the ISO to enable **autoinstall mode** (no confirmation prompt)  
- Builds a new bootable ISO  
- Creates and boots a **Proxmox VM** that installs Ubuntu 24.04 completely hands-free 🎯  

---

## ⚡ Key Features

| Feature | Description |
|----------|--------------|
| ✅ **100% Hands-Free Install** | No prompts — installs automatically |
| 🧑‍💻 **Custom Users & Passwords** | Root & Admin with full SSH access |
| 🔐 **Root SSH Access Enabled** | Secure login out of the box |
| 🧱 **ZFS Support** | Automatically creates ZFS-based storage |
| 🧩 **Hybrid BIOS + UEFI Boot** | Works on any Proxmox VM configuration |
| 💾 **Cloud-Init Integration** | Built-in NoCloud configuration |
| 🔧 **Customizable Parameters** | Hostname, VM ID, Storage, RAM, CPU, etc. |
| 💡 **Proxmox VM Auto-Creation** | Creates and boots a VM automatically |

---

## 🧰 Requirements

- Proxmox VE 8.0 or later  
- Internet connectivity  
- Root access  
- Minimum 10 GB free storage in `/var/lib/vz/template/iso`

---

## ⚙️ Installation & Usage

### 1️⃣ Save the Script

Create the file:

```bash
nano /root/auto-ubuntu-autoinstall.sh
