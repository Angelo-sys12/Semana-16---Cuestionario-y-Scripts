#!/bin/bash
set -euo pipefail

echo "[*] Iniciando la reversión del entorno de red (DevSecOps Reset)..."

# Desactivar el mecanismo de mitigación de la memoria de sockets del Kernel
sysctl -w net.ipv4.tcp_syncookies=0

# Remover de forma exacta las reglas inyectadas durante la mitigación
iptables -D INPUT -p tcp --syn --dport 80 -m limit --limit 10/s --limit-burst 15 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --syn --dport 80 -j DROP 2>/dev/null || true
iptables -D INPUT -p tcp --dport 80 -m string --string "db.sql" --algo bm -j DROP 2>/dev/null || true

echo "[+] El firewall Netfilter ha sido restaurado a su línea base original de pruebas."
