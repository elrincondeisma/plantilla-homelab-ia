# Seguridad: qué se automatiza, qué no, y qué frena al agente

Un agente con shell de root en tus nodos puede arreglar mucho y romper más. Esta plantilla no
confía en que el modelo se porte bien: pone barreras que funcionan aunque se equivoque o alguien
le meta instrucciones por un texto ajeno (un correo, una web, el log de un servicio).

## La regla que ordena todo

El procedimiento peligroso no lo improvisa el LLM: está escrito en un script revisado.

Actualizar un contenedor con copia previa, verificar y volver atrás si falla es un procedimiento
con muchos pasos y varios modos de fallo. Si el modelo lo reconstruye cada vez a base de comandos
sueltos, un día lo reconstruirá mal. Por eso vive en `scripts/homelab-actualizar`, que se lee una
vez, se prueba y se instala en los nodos. El agente lo invoca y cuenta el resultado. Lo peor que
puede pasar si alguien consigue dirigir al agente es que se dispare una actualización con su copia
y su marcha atrás, no un `apt` a pelo sobre producción de madrugada.

## Tres capas distintas

Son independientes y se complementan. Ninguna sustituye a otra.

1. Permisos de Claude Code (`permissions.deny` y `permissions.ask` en `.claude/settings.json`).
   Casan el comando por su forma. `deny` prohíbe `pct destroy *` y compañía cuando el comando
   empieza así. `ask` pide confirmación humana para cada `ssh` y `scp`. Son reglas sobre el
   comando que lanza el agente en tu máquina.
2. El hook `PreToolUse` (`.claude/hooks/bloquear-destructivo.sh`). Es un script que recibe el
   comando completo antes de ejecutarlo y puede vetarlo. Es el que mira dentro del `ssh "..."`.
   Un `deny` como `Bash(pct destroy *)` no ve nada en `ssh nodo2 "pct destroy 101"`, porque ese
   comando empieza por `ssh`, y el `destroy` va dentro de una cadena que se ejecuta en otra
   máquina. El hook trocea el comando, quita comillas y analiza también lo que va dentro de
   `ssh host "..."`, `bash -c '...'`, `$(...)` y lo encadenado con `&&`, `;` y `|`.
3. Los permisos del lado remoto. Lo que el sistema de destino deja hacer a la clave que se usa.
   Es la única capa que no depende de tu máquina. El ejemplo `ejemplos/vigilante/` la usa: una
   clave que solo puede ejecutar cinco consultas.

Un `deny` evita el descuido directo y es barato. El hook cubre el rodeo más habitual (meter la
orden dentro de `ssh`). La capa remota es la que aguanta cuando fallan las dos anteriores.

### Lo que el hook deniega

`pct destroy`, `qm destroy`, `--purge`, `pvesm free`, `pvecm delnode`, `mkfs` y `mkfs.*`,
`dd` con `of=/dev/...` (salvo `/dev/null`), `rm` recursivo sobre `/`, y el borrado de copias
`vzdump-*` (con `rm`, `find -delete` o `pvesm free`) o de ficheros en un directorio absoluto
`.../dump/`. Si falta `jq` o la entrada no es JSON, también deniega (falla cerrado).

Al denegar sale con código 2 y un mensaje en español que dice qué ha parado y cómo hacerlo a mano
desde una terminal tuya.

### Lo que el hook no puede hacer

Es una red de seguridad, no un intérprete de shell. No resuelve variables
(`X=destroy; pct $X 101`), ni expansiones de llaves, ni base64 (`echo cGN0... | base64 -d | sh`),
ni un script escrito antes en un fichero. Tampoco cubre otras vías de borrado, como
`pvesh delete /nodes/nodo1/lxc/101`. Ante la duda, bloquea: puede dar falsos positivos (un
`mkfs` dentro de un `echo` suelto, o `apt-get remove --purge`). Cuando eso pase, lanzas tú el
comando.

Los permisos `deny` de `settings.json` incluyen además `pct restore` y `qmrestore`, que el hook
no mira: restaurar sobrescribe el disco actual, y eso lo decide una persona.

## Lo que no se automatiza, y por qué

- Restaurar copias. Un `vzdump` restaurado sobrescribe el disco que hay ahora. Si la copia es
  vieja o el fallo era otro, se pierde lo que se había hecho desde entonces. Por eso el rollback
  automático solo existe sobre snapshots, que son instantáneos y se descartan sin más. Un guest
  sin snapshot que falla queda en cuarentena, con la copia intacta y un aviso.
- Home Assistant OS y sus addons. Actualizar HAOS reinicia la máquina virtual entera, y el agente
  de qemu desaparece con ella. Un script que vigile la actualización leería ese reinicio como un
  fallo y revertiría una actualización que iba bien. Los addons pueden además romper integraciones
  que dependen de hardware (Zigbee, Z-Wave) de formas que ninguna comprobación genérica detecta.
  Se informa de lo pendiente y lo aplica una persona.
- Imágenes de Docker con base de datos. Un salto de versión mayor puede migrar el esquema de la
  base de datos, y entonces volver al snapshot ya no basta: la copia previa tiene el esquema
  viejo y los datos nuevos que se escribieron entre medias se pierden, o al revés. La plantilla
  actualiza solo el sistema operativo (apt, apk), no imágenes.
- Reinicios y actualizaciones de nodos. Con un cluster de dos nodos, apagar uno deja al otro sin
  quórum. Si hace falta, se hace a mano y con cabeza.
- Las VM. Una VM exige agente de invitado y un procedimiento propio. `homelab-actualizar` las
  lista en el plan y no las toca.

## El agente que vigila, sin claves de escritura

Un agente que cuenta cada mañana cómo está el homelab no necesita poder cambiarlo. En
`ejemplos/vigilante/` hay una clave SSH dedicada cuyo `authorized_keys` fuerza un envoltorio
(`homelab-lectura`). El envoltorio lee `SSH_ORIGINAL_COMMAND` y deja pasar una lista cerrada, por
igualdad exacta de texto: estado del actualizador, cuarentena, estado de almacenamientos y de
cluster, y las copias de un almacén fijado en el propio script. Todo lo demás sale con error y
queda en syslog. No hay `eval` ni se pasa nada a una shell, así que no hay inyección posible
mediante `;`, `&&` o `$(...)`.

Si alguien consigue dirigir a ese agente con un texto ajeno, lo peor que puede hacer es leer cinco
cosas. Es la diferencia entre una clave de root y una clave de lectura.

## Una trampa de la verificación

`homelab-actualizar` verifica comparando lo que sirve el guest antes y después, y entre otras cosas
mira los puertos en escucha. Un servidor multimedia abría en cada arranque un puerto auxiliar
aleatorio solo en localhost, y la comparación lo daba como un servicio que ya no escucha: el guest
pasó semanas en cuarentena sin ningún problema real. Por eso la verificación ignora por defecto
los puertos que escuchan solo en `127.0.0.1` o `::1`, y la configuración admite una lista de
puertos ignorados por guest (`PUERTOS_IGNORADOS`). Un puerto expuesto que desaparece sigue
contando como fallo.

## Antes de fiarte de esto

Prueba las barreras. `bash tests/probar-hook.sh` pasa una batería de comandos por el hook sin
tocar nada. Prueba también la marcha atrás sobre un guest real que no importe:
`homelab-actualizar guest <id> --ensayo-fallo`. Es la única forma de saber que funciona antes de
necesitarla.
