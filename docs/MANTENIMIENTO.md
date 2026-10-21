# Mantenimiento automático con homelab-actualizar

`scripts/homelab-actualizar` actualiza el sistema operativo de los contenedores de un nodo, con
copia previa, verificación y marcha atrás. Se instala en cada nodo. Un timer de systemd lanza una
ronda cada madrugada.

## Instalación en un nodo

```
scp scripts/homelab-actualizar nodo1:/usr/local/bin/homelab-actualizar
scp scripts/homelab-actualizar.conf.ejemplo nodo1:/etc/homelab-actualizar.conf
scp scripts/homelab-actualizar.service scripts/homelab-actualizar.timer nodo1:/etc/systemd/system/
ssh nodo1 "chmod 755 /usr/local/bin/homelab-actualizar && chmod 644 /etc/homelab-actualizar.conf"
ssh nodo1 "systemctl daemon-reload && systemctl enable --now homelab-actualizar.timer"
```

Edita primero la configuración. Con dos nodos, pon el timer del segundo a otra hora (hay un
drop-in de ejemplo en el propio `.timer`) para que no actualicen a la vez. Prueba siempre antes
con `plan` y con `--simular`.

## El ciclo

Por cada guest, si no hay nada pendiente no se le hace copia ni se le toca. Si lo hay:

1. Copia previa. Snapshot si el guest lo admite. Si no (`SIN_SNAPSHOT`), un `vzdump` al almacén
   configurado.
2. Se saca una foto de lo que el guest sirve: puertos en escucha (leídos de `/proc/net/tcp`),
   unidades de systemd en `failed` y contenedores de Docker en marcha.
3. Se actualiza el sistema (`apt` o `apk`).
4. Se reinicia solo si el sistema lo pide (`/run/reboot-required`).
5. Se vuelve a sacar la foto y se compara.
6. Si todo coincide, se borra el snapshot. Si no, se vuelve al snapshot, se comprueba que el guest
   queda sano, se pone en cuarentena y se avisa.

## La verificación es por diferencia

No hay una tabla de puertos por guest que mantener. Falla si desaparece un puerto, aparece una
unidad caída nueva o no vuelve un contenedor. Un guest que ya estaba roto antes sigue pareciendo
sano: esto detecta empeoramientos, no problemas previos. Es una limitación asumida.

Los puertos que escuchan solo en loopback no cuentan (`IGNORAR_LOOPBACK=1`), y
`PUERTOS_IGNORADOS="101:8080,5555 *:9999"` permite descartar otros por guest. Ver la trampa en
`docs/SEGURIDAD.md`.

## Comandos

```
homelab-actualizar plan [--solo 101,102] [--refrescar]   # qué debe cada guest, solo lectura
homelab-actualizar guest 101                             # un guest, ciclo completo
homelab-actualizar ronda                                 # todos los guests (lo que lanza el timer)
homelab-actualizar estado                                # último informe y cuarentena
homelab-actualizar cuarentena lista
homelab-actualizar cuarentena quitar 101                 # tras revisar a mano
```

Opciones:

- `--simular`: no cambia nada y no escribe estado ni log; enseña lo que haría. Las lecturas
  (estado, paquetes pendientes, la foto previa) sí se ejecutan.
- `--ensayo-fallo`: hace el ciclo y finge que la verificación falla, para ensayar la vuelta al
  snapshot en un guest real. Necesita snapshot. No deja el guest en cuarentena si la vuelta sale
  bien.
- `--solo a,b,c`: limita `plan` y `ronda` a esos ids.
- `--refrescar`: en `plan`, actualiza antes el índice de paquetes del guest. Sin él se usa el
  índice que ya tenga, que puede estar viejo.

## Configuración

`/etc/homelab-actualizar.conf` (o el fichero de la variable `HOMELAB_ACTUALIZAR_CONF`). Es un
fichero de shell; el script se niega a leerlo si lo puede escribir cualquiera. Las opciones están
comentadas en `scripts/homelab-actualizar.conf.ejemplo`: `EXCLUIR`, `SIN_SNAPSHOT`,
`ALMACEN_COPIAS`, `ESPERA_ARRANQUE`, `IGNORAR_LOOPBACK`, `PUERTOS_IGNORADOS` y `AVISO_COMANDO`.

`AVISO_COMANDO` es un ejecutable que recibe el mensaje como primer argumento. Úsalo para mandar
una notificación push o un correo cuando algo falla. No hay valores por defecto con servicios
concretos.

## Dónde deja las cosas

| Qué | Dónde |
|---|---|
| Informe (una línea JSON por guest y ejecución) | `/var/lib/homelab-actualizar/informe.jsonl` |
| Cuarentena | `/var/lib/homelab-actualizar/cuarentena/<id>` |
| Bitácora | `/var/log/homelab-actualizar.log` |

## Lo que la plantilla no hace

- No actualiza ni reinicia nodos, solo guests. Reiniciar un nodo en un cluster de dos exige
  cuidar el quórum y se hace a mano.
- No actualiza VM, Home Assistant OS ni imágenes de Docker (ver `docs/SEGURIDAD.md`).
- No restaura copias `vzdump`. Un guest sin snapshot que falla se queda en cuarentena con la copia
  intacta.
- No borra las copias `vzdump` que crea: la retención es cosa del almacén (`prune-backups`).

## Pruebas

`bash tests/probar-actualizar.sh` ejecuta el script contra `pct`, `qm` y `vzdump` simulados, sin
tocar ningún nodo: plan, simulación, éxito, fallo con vuelta al snapshot, ensayo de fallo,
puertos ignorados, copia con vzdump y cuarentena.
