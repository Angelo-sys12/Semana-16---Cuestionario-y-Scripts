#!/bin/bash
# Asegurar la detención si un comando falla o hay variables sin definir
set -euo pipefail

INTERFACE="ens33"

echo "[*] Iniciando ingeniería de mitigación de vectores concurrentes..."

# =====================================================================
# 🔄 PASO 1: IDEMPOTENCIA (Limpieza Quirúrgica Previa)
# =====================================================================
# Eliminamos las reglas idénticas si ya existían para evitar duplicados,
# protegiendo accesos administrativos activos (como SSH) de un flusheo destructivo.
iptables -D INPUT -p tcp --syn --dport 80 -m limit --limit 10/s --limit-burst 15 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --syn --dport 80 -j DROP 2>/dev/null || true
iptables -D INPUT -p tcp --dport 80 -m string --string "db.sql" --algo bm -j DROP 2>/dev/null || true

# =====================================================================
# ⚡ PASO 2: DEFENSA EN CAPA 4 (Rate Limiting + SYN Cookies)
# =====================================================================
echo "[*] Configurando Rate Limiting en Capa 4 y mecanismos de Kernel..."

# Activación de TCP SYN Cookies a nivel de Kernel para evitar el agotamiento del backlog
sysctl -w net.ipv4.tcp_syncookies=1

# Regla A: Aceptar solo un flujo controlado de paquetes SYN legítimos
iptables -A INPUT -p tcp --syn --dport 80 -m limit --limit 10/s --limit-burst 15 -j ACCEPT

# Regla B: Descartar de inmediato el exceso volumétrico del ataque SYN Flood
iptables -A INPUT -p tcp --syn --dport 80 -j DROP

# =====================================================================
# 🔍 PASO 3: DEFENSA EN CAPA 7 (Deep Packet Inspection por Strings)
# =====================================================================
echo "[*] Implementando Deep Packet Inspection (Filtro String) en Capa 7..."

# Regla C: Interceptar peticiones al recurso pesado usando el algoritmo Boyer-Moore (bm)
iptables -A INPUT -p tcp --dport 80 -m string --string "db.sql" --algo bm -j DROP

echo "[+] ¡Plan de acción desplegado de manera exitosa!"
