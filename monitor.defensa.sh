#!/bin/bash
# Modo estricto para asegurar estabilidad operativa
set -euo pipefail

INTERFACE="ens33"
UMBRAL_PKTS=5000  # Umbral de peligro: paquetes entrantes por segundo

# Obtener la cantidad de paquetes recibidos en un intervalo de 1 segundo
PKTS_INI=$(cat /sys/class/net/$INTERFACE/statistics/rx_packets)
sleep 1
PKTS_FIN=$(cat /sys/class/net/$INTERFACE/statistics/rx_packets)

PKTS_SEC=$((PKTS_FIN - PKTS_INI))

echo "[*] Tráfico actual en $INTERFACE: $PKTS_SEC paquetes/seg"

# Evaluación lógica del umbral de peligro
if [ "$PKTS_SEC" -gt "$UMBRAL_PKTS" ]; then
    echo "[!] ALERTA: Tráfico anómalo detectado ($PKTS_SEC p/s). Activando mitigación..."
    # Ejecuta el script de defensa pasándole la ruta absoluta
    /home/alumno/defensa.sh
else
    echo "[+] Tráfico estable. El sistema opera dentro de los márgenes seguros."
fi
