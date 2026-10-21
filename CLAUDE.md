# Homelab Proxmox: puesto de administración

Este repo es un puesto de administración por SSH. No tiene código de aplicación: solo
documentación, un par de scripts que se instalan en los nodos y las barreras de seguridad de
Claude Code (`.claude/`). Todo lo que se hace sobre el homelab se hace conectando por SSH a los
nodos Proxmox.

Sustituye los nombres de ejemplo (`nodo1`, `nodo2`, `nas`) por los tuyos al adoptar la plantilla.

## Conectarse

Los nodos van por clave SSH. Alias de ejemplo en `~/.ssh/config`:

```
Host nodo1
  HostName 192.0.2.11
  User root
  IdentityFile ~/.ssh/id_ed25519
Host nodo2
  HostName 192.0.2.12
  User root
  IdentityFile ~/.ssh/id_ed25519
```

- Antepón siempre `export LC_ALL=C;` a los comandos remotos. Un cliente con otro locale manda un
  `LC_CTYPE` que el nodo no tiene y salen avisos de `setlocale`, que ensucian la salida y
  pueden romper scripts que la leen.
  `ssh nodo1 "export LC_ALL=C; pvesm status"`
- `pvesh` funciona desde cualquier nodo del cluster y enruta solo al que toque.
- Cada `ssh` y cada `scp` pide confirmación (está en `permissions.ask`). Es a propósito.

## Inventario en vivo

Esta documentación no lleva lista de guests: se queda vieja. La foto real es:

```
ssh nodo1 "export LC_ALL=C; pvesh get /cluster/resources --type vm"
```

Consúltala siempre antes de fiarte de una lista antigua. Los ids son únicos en el cluster, pero un
guest cambia de nodo con una migración y los ids se reutilizan.

## Reglas

1. Confirma lo destructivo. Borrar, restaurar, sobrescribir, formatear, sacar un nodo del cluster
   o parar algo que sirve tráfico: antes de lanzarlo, di qué vas a hacer y espera un sí
   explícito. Lo irreversible lo bloquea el hook (ver `docs/SEGURIDAD.md`).
2. Copia antes de tocar ficheros del sistema. Antes de editar algo de `/etc` o similar en un nodo
   o en un guest: `cp -a fichero fichero.bak.<motivo>-<fecha>`, por ejemplo
   `cp -a /etc/fstab /etc/fstab.bak.ampliar-disco-2026-03-14`.
3. Verifica después de actuar. Un comando que termina sin error no prueba que el servicio
   funcione. Comprueba el resultado: el estado del guest, el puerto, la respuesta HTTP, el log.
4. Un cambio cada vez, y comprobado, antes de pasar al siguiente.
5. El procedimiento peligroso no se improvisa. Si existe un script revisado para ello
   (`scripts/homelab-actualizar`), se invoca; no se reescribe a mano en la sesión.
6. Si el hook bloquea algo, no busques un rodeo. Cuéntaselo al usuario: la orden la lanza él
   desde su terminal si de verdad la quiere.
7. Nada de secretos en el repo: viven en `.env` (ignorado por git; `.env.example` lista los
   nombres) o en el propio nodo.

## Comandos habituales

```
ssh nodo1 "export LC_ALL=C; pct list"                          # contenedores del nodo
ssh nodo1 "export LC_ALL=C; qm list"                           # máquinas virtuales
ssh nodo1 "export LC_ALL=C; pvecm status"                      # cluster y quórum
ssh nodo1 "export LC_ALL=C; pvesm status"                      # almacenamientos
ssh nodo1 "export LC_ALL=C; homelab-actualizar plan"           # qué debe cada guest, solo lectura
ssh nodo1 "export LC_ALL=C; homelab-actualizar estado"         # último informe
ssh nodo1 "export LC_ALL=C; homelab-actualizar guest 101"      # un guest, con copia y marcha atrás
ssh nodo1 "export LC_ALL=C; homelab-actualizar cuarentena lista"
```

Para ver qué haría sin cambiar nada, añade `--simular`. Para ensayar la marcha atrás sobre un
guest real, `--ensayo-fallo`.

## Trampas

Aquí se apunta lo que ya costó tiempo, para no pagarlo dos veces. Una entrada por trampa: qué
parecía, qué era de verdad y cómo se comprueba. Empieza vacía; este es el formato:

- Ejemplo (genérico). Un servicio publicado tras Cloudflare dejó de responder para parte de los
  usuarios a ciertas horas. El contenedor estaba sano y el proxy también. La causa era un bloqueo
  de IPs por orden judicial (el de LaLiga durante los partidos) que afecta a rangos de Cloudflare y
  tumba el servicio solo desde algunas redes. Cómo se comprueba: probar el servicio por una ruta
  distinta (otra red, otra VPN) antes de tocar nada en el homelab, y mirar si el fallo coincide
  con el horario de los partidos. Si todo está sano por dentro, el problema está fuera.

## Dónde mirar

- `docs/SEGURIDAD.md`: qué no se automatiza y por qué, las barreras (permisos, hook, agente que
  vigila) y cómo se complementan.
- `docs/MANTENIMIENTO.md`: cómo funciona `homelab-actualizar`: ciclo, configuración, timers,
  cuarentena y marcha atrás.
- `ejemplos/vigilante/`: un agente que vigila el homelab sin claves de escritura.
- `tests/`: `bash tests/probar-hook.sh` y `bash tests/probar-actualizar.sh`.
