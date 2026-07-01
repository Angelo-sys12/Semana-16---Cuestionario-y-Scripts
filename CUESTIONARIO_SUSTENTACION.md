# Cuestionario Técnico de Sustentación Oral - Laboratorio 15
**Estudiantes:** Angelo Huayre Salvador - Deyvi Baldera Chapoñan (alumno@webserver)

A continuación, detallamos nuestras respuestas técnicas para la defensa del laboratorio, basadas directamente en los hallazgos que observé en mi servidor y en las decisiones de diseño de mi arquitectura de mitigación.

---

### Pregunta 1: El atacante usó `--rand-source` (IP Spoofing) enviando paquetes SYN. Físicamente, el handshake TCP nunca se completa. Entonces, ¿por qué este ataque logra consumir recursos del servidor y causar latencia si la conexión nunca se establece realmente?

**Mi respuesta:** El consumo crítico de recursos no ocurre porque se complete una conexión HTTP, sino por la memoria que el Kernel de mi servidor tiene que reservar para cada paquete incompleto. 

Cuando recibo un paquete `SYN`, la pila de red de mi Linux reserva de inmediato una ranura física de memoria en el **Backlog de conexiones semiestablecidas** (dejando el socket en estado `SYN-RECV`). Mi servidor asigna buffers de memoria, responde con un `SYN-ACK` y se queda esperando un paquete `ACK` final que nunca va a llegar porque las IPs de origen son falsas. 

Esas conexiones se quedan "atascadas" consumiendo memoria RAM en el espacio del Kernel hasta que expira el temporizador (*timeout*). Como la inundación que sufrí era masiva, mi cola de conexiones se saturó al 100%, provocando que cuando un usuario legítimo intentaba abrir el juego 2048, el Kernel simplemente rechazaba su paquete `SYN` por falta de sockets disponibles.

---

### Pregunta 2: Su script usa la regla ESTABLISHED,RELATED para dejar pasar el tráfico legítimo. ¿Qué pasaría con los jugadores del juego 2048 si olvidaran poner esa regla y solo dejaran el Rate Limiting estricto?

**Mi respuesta:** Si yo hubiera olvidado poner esa regla de estado al principio de mi script, **los usuarios legítimos que ya estaban jugando habrían experimentado un congelamiento total o desconexiones del juego**.

Sin la regla `ESTABLISHED,RELATED`, cada uno de los paquetes de datos que envía un jugador activo (por ejemplo, cada vez que mueve las flechas del juego 2048) tendría que pasar obligatoriamente por la regla de *Rate Limiting* estricta que puse abajo. Al procesarse de forma lineal, las jugadas legítimas agotarían rapidísimo mi cuota permitida (`--limit 10/s --limit-burst 15`). El firewall empezaría a tratar a mis usuarios reales como si fueran parte del ataque masivo, aplicándoles un `DROP` y tirándoles la conexión. Esa regla me sirvió para crear una "vía rápida" para el tráfico que ya fue validado previamente.

---

### Pregunta 3: En su defensa bloquearon la cadena 'db.sql' usando el módulo string de iptables. ¿Qué sucedería si el servidor web estuviera configurado con HTTPS (puerto 443) en lugar de HTTP (puerto 80)? ¿Seguiría funcionando esta regla de iptables? ¿Por qué?

**Mi respuesta:** **No, mi regla de iptables dejaría de funcionar por completo.** El módulo `--string` realiza una inspección profunda de paquetes (Deep Packet Inspection) buscando texto plano a nivel de bytes dentro de la carga útil (*payload*) en Capa 7.

Si mi servidor web utilizara HTTPS en el puerto 443, se introduce la capa de cifrado TLS/SSL. Esto significa que toda la petición (la URL, los encabezados y la palabra `"db.sql"`) viajaría completamente encriptada desde el navegador del cliente hasta el servidor web. Como `iptables` procesa los paquetes a nivel de Kernel *antes* de que lleguen a la aplicación (Apache/Nginx) para ser descifrados con la llave privada, el firewall solo vería caracteres criptográficos aleatorios. El patrón `"db.sql"` jamás coincidiría y el ataque pasaría limpio.

---

### Pregunta 4: En su código utilizan iptables -A. ¿Qué pasaría exactamente en la tabla de ruteo del kernel si configuraran un cron job para que ejecute su script cada 5 minutos durante un mes y olvidan poner el comando para limpiar reglas (iptables -F o -D)?

**Mi respuesta:** Lo que provocaría sería un **cuello de botella masivo en el rendimiento del procesador de mi servidor** debido a la redundancia extrema de reglas en el Kernel.

El comando `-A` (*Append*) añade la regla al final de la cadena de forma ciega. Si mi script se ejecutara cada 5 minutos durante un mes sin una limpieza previa con `-D` o `-F`, terminaría inyectando exactamente las mismas reglas duplicadas unas 8,640 veces. 

Como Netfilter recorre las reglas en orden secuencial (de arriba hacia abajo) por cada paquete que entra a la tarjeta de red, la CPU de mi servidor gastaría millones de ciclos de reloj evaluando la misma lógica miles de veces de forma redundante. Esto elevaría drásticamente la latencia de red y terminaría sobrecargando la CPU por interrupciones de software (*softirqs*), autogenerándome una denegación de servicio interna.

---

### Pregunta 5: Mencionaron que el servidor tenía alta carga de CPU/Disco (I/O) durante el ataque. Si el disco llega al 100% de uso, ¿cómo afecta esto a la escritura de los logs de Apache (access.log) y qué impacto tiene en nuestro diagnóstico?

**Mi respuesta:** Cuando mi disco colapsó al 100% de uso (como verifiqué en la métrica del `%util` en `iostat`), las operaciones físicas de escritura entraron en un estado de bloqueo total.

1. **Impacto en Apache:** Apache no puede vaciar los buffers de memoria hacia el archivo `access.log`. Al no poder escribir en el almacenamiento, los hilos de trabajo (*Workers*) de mi servidor web se quedan esperando a que el sistema operativo complete la llamada `write()`, lo que termina congelando la atención de los usuarios en la web.
2. **Impacto en mi diagnóstico:** Destruye la visibilidad en tiempo real. Si yo intentaba hacer un `tail -f /var/log/apache2/access.log` para ver las IPs atacantes, el archivo se quedaba completamente congelado o mostraba las líneas con minutos de retraso. Esto me podría haber engañado haciéndome pensar que el ataque ya se había detenido cuando en realidad el disco simplemente estaba colapsado y represando la información.

---

### Pregunta 6: En el temario vimos TCP Wrappers (hosts.allow / hosts.deny). ¿Por qué un ataque SYN Flood no puede ser detenido por TCP Wrappers, obligándolos a usar iptables/nftables en su lugar?

**Mi respuesta:** No puedo usar TCP Wrappers para mitigar un SYN Flood porque **actúa en una capa demasiado alta de la pila OSI (Capa 7)** en comparación con el ataque.

TCP Wrappers es una librería en el Espacio de Usuario que se activa únicamente *después* de que la conexión TCP ya completó el acuerdo de tres capas (*Three-Way Handshake*) a nivel de Kernel y la aplicación ejecutó la llamada `accept()`. Como el ataque SYN Flood ataca precisamente en las Capas 3 y 4 enviando paquetes falsificados continuos, satura los sockets del sistema operativo mucho antes de que la aplicación sepa que existe una conexión. El servidor cae en el espacio de Kernel, por lo que la defensa debe ser implementada ahí abajo con Netfilter (`iptables`), antes de que toque las capas superiores.

---

### Pregunta 7: ¿Qué pasaría si el atacante, usando IP Spoofing, falsifica la dirección IP de nuestra propia puerta de enlace (Gateway 10.160.10.2)? ¿Su script de Rate Limiting terminaría bloqueando el tráfico legítimo de salida a internet de nuestro propio servidor?

**Mi respuesta:** **No, mi tráfico legítimo de salida a Internet no se vería afectado.** Esto se debe a que acoplé mis reglas defensivas estrictamente a la cadena de entrada **`INPUT`** de la tabla *filter* y apuntando específicamente como destino al puerto local 80 (`--dport 80`).

Cuando mi servidor genera tráfico saliente (por ejemplo, peticiones hacia Internet o actualizaciones), el flujo de datos se procesa en la cadena `OUTPUT`, la cual mantengo completamente limpia y libre de restricciones. Los paquetes de respuesta que regresan entran a puertos efímeros aleatorios y no al puerto 80, por lo que no hacen *match* con la regla de control de tasa. El único impacto es que si el atacante falsifica la IP de mi Gateway, yo mitigaré el ataque descartando (`DROP`) el exceso en la cadena `INPUT`, protegiendo mis sockets sin romper el enrutamiento base de salida.

---

### Pregunta 8: Ustedes proponen usar [Ej. Fail2Ban / Cloudflare / WAF] como alternativa. ¿Cómo maneja esa solución el problema de los "falsos positivos", es decir, bloquear a un aula entera de universidad que sale a internet bajo una misma IP pública (NAT)?

**Mi respuesta:** Para evitar este problema de "Efecto NAT Masivo" en entornos empresariales reales, no podemos depender únicamente del bloqueo por Dirección IP en Capa 3. Las soluciones avanzadas que propongo mitigan esto subiendo el análisis a Capa 7:

1. **Galletas de Sesión y Huellas Digitales (Device Fingerprinting):** Herramientas como Cloudflare inyectan *cookies* HTTP cifradas y analizan variables del navegador del cliente. Así, diferencian computadoras individuales aunque compartan la misma IP pública corporativa.
2. **Uso del encabezado `X-Forwarded-For`:** Si el tráfico pasa por un proxy intermedio, el WAF lee este encabezado que transporta la IP privada real del cliente original, permitiéndome bloquear exclusivamente al dispositivo hostil dentro del aula de la universidad.
3. **Desafíos Interactivos Silenciosos (JavaScript Challenges):** En lugar de aplicar un bloqueo `DROP` directo, el WAF le envía un reto matemático interactivo al navegador. Un usuario legítimo lo resuelve en milisegundos en segundo plano, mientras que las herramientas automatizadas (bots) fallan el reto y quedan aisladas de forma individual.

---

### Pregunta 9: Si el atacante cambia de estrategia y, en lugar de descargar un archivo de 2MB, envía 100,000 peticiones por segundo al index.html (que pesa 1KB), ¿su script de defensa actual seguiría siendo efectivo? ¿Por qué?

**Mi respuesta:** **Mi script actual sería efectivo para proteger la red en Capa 4, pero mi servidor sufriría una denegación de servicio en Capa 7.**

Por un lado, la regla de *Rate Limiting* seguiría protegiendo el sistema operativo, descartando inmediatamente el grueso de las 100,000 peticiones en el cortafuegos. El Kernel no colapsaría. 

Sin embargo, mi regla en Capa 7 basada en el filtro de cadenas (`-m string --string "db.sql"`) quedaría totalmente obsoleta porque el atacante ahora pide un recurso legítimo (`index.html`). Dado que el cortafuegos dejará pasar la cuota controlada de 10 a 15 conexiones por segundo, si esa cuota es acaparada por completo por las peticiones de los bots del atacante, mis usuarios legítimos se quedarían sin margen de entrada (*starvation*). Para resolver esta mutación, tendría que evolucionar mi configuración limitando las peticiones por IP usando el módulo `limit_req` directamente en mi servidor web.

---

### Pregunta 10: Según el paso 6 de la metodología HP (Medidas Preventivas), el objetivo es que esto no vuelva a ser un problema manual. Si tuvieran que automatizar este diagnóstico para que les llegue una alerta a Telegram/Slack antes de que el servidor caiga, ¿qué herramienta de observabilidad de Linux implementarían y qué métrica exacta monitorearían?

**Mi respuesta:** Para no depender de revisiones manuales en el futuro, yo implementaría una arquitectura de observabilidad basada en **Prometheus** con **Node Exporter** en mi servidor, centralizando las alertas y trazas hacia Slack o Telegram mediante **Alertmanager y Grafana**.

Para capturar la anomalía antes de que el servidor web se sature por completo, configuraría alarmas automáticas basadas en tres métricas clave del sistema:

1. **Métrica de Sockets en estado de alerta:** Monitorearía el contador de sockets TCP usando la métrica de Prometheus `node_sockstat_TCP_tw` y vigilando picos anormales de conexiones atascadas en estado `SYN_RECV`.
2. **Métrica de Volumen en la Interfaz de Red:** Mediría la derivada de paquetes entrantes por segundo en mi interfaz mediante la consulta de Prometheus: `rate(node_network_receive_packets_total{device="ens33"}[1m])`. Si la tasa supera mi línea base segura de laboratorio (ej. más de 5000 paquetes por segundo), la alerta se dispara de inmediato.
3. **Métrica de Cuello de Botella de Hardware:** Monitorearía el indicador de CPU en espera de disco: `node_cpu_seconds_total{mode="iowait"}`. Si el `%iowait` sube del 50% de forma sostenida por dos minutos, significa que están intentando agotar los recursos I/O del disco duro (Capa 7), alertando a mi equipo de seguridad antes del colapso del servicio.
