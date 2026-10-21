# Vigilante de solo lectura

Un agente (o un cron) que mira el homelab cada mañana y cuenta qué tal está, sin poder cambiar
nada. La idea es que su clave SSH solo sirva para cinco consultas.

## Piezas

- `homelab-lectura`: envoltorio que se instala en cada nodo. Lee `SSH_ORIGINAL_COMMAND` y solo
  deja pasar cinco órdenes, por igualdad exacta: `homelab-actualizar estado`,
  `homelab-actualizar cuarentena lista`, `pvesm status`, `pvecm status` y
  `pvesm list <almacén> --content backup` (con el almacén fijado dentro del script). Lo demás da
  error y queda en syslog con `logger`.
- `authorized_keys.ejemplo`: la línea que fuerza el envoltorio con `restrict`.
- `parte.sh`: el script que corre el agente. Llama por ssh a cada nodo, junta el resultado en un
  texto corto y lo imprime.
- `tests/probar-lectura.sh`: prueba el envoltorio en local con `SSH_ORIGINAL_COMMAND` simulado.

## Montarlo

1. Genera una clave solo para esto: `ssh-keygen -t ed25519 -f ~/.ssh/id_vigilante -C vigilante-lectura`.
2. En cada nodo, copia `homelab-lectura` a `/usr/local/bin/` (root:root, 755) y ajusta `ALMACEN`.
3. Añade la clave pública a `/root/.ssh/authorized_keys` del nodo con el formato de
   `authorized_keys.ejemplo`, sustituyendo el texto `AAAA…EJEMPLO` por tu clave.
4. Comprueba que solo pasa lo previsto:
   `ssh -i ~/.ssh/id_vigilante root@nodo1 "pvesm status"` responde y
   `ssh -i ~/.ssh/id_vigilante root@nodo1 "pct list"` falla con código 126.
5. Ajusta las variables de `parte.sh` (`NODOS`, `CLAVE_VIGILANTE`, `ALMACEN`) y pruébalo a mano.

Las órdenes se mandan tal cual, sin `export LC_ALL=C;` delante: el envoltorio solo acepta el texto
exacto y fija el idioma él mismo.

## Programarlo

Con Hermes Agent, una tarea en modo script y sin LLM: el script es la tarea y su salida se entrega
tal cual. Copia `parte.sh` a `~/.hermes/scripts/` y crea la tarea:

```
hermes cron create "15 8 * * *" --script parte.sh --no-agent --deliver telegram --name "Parte del homelab"
```

Cambia `--deliver` por el destino que uses. Las opciones salen de `hermes cron create --help`;
revísalas si tu versión es distinta.

Con cron normal, desde una máquina que tenga la clave:

```
15 8 * * * /ruta/a/parte.sh | mail -s "Parte del homelab" tu@correo.example
```

## Probar el envoltorio

```
bash ejemplos/vigilante/tests/probar-lectura.sh
```

Pasa las cinco órdenes permitidas contra stubs y comprueba que se rechazan `pct list`,
`pct destroy 99999`, `bash`, `homelab-actualizar estado; rm -rf /`, `pvesm status && id`, la cadena
vacía y otra veintena de variantes.
