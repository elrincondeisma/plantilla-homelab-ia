# plantilla-homelab-ia

Una plantilla para administrar un homelab Proxmox con Claude Code sin jugarte los datos. Es un
repo sin código de aplicación: lo abres con Claude Code y desde ahí el agente se conecta por SSH a
tus nodos. Lo que trae son las barreras para que un fallo suyo, o un texto ajeno que lo despiste,
no acabe borrando un contenedor o una copia de seguridad.

La saqué de un repo real de administración y le quité todo lo personal.

## Qué trae

- `CLAUDE.md` con las instrucciones del agente: cómo conectarse (siempre con `export LC_ALL=C;`
  delante), cómo ver el inventario en vivo, las reglas de trabajo y una sección de trampas para
  ir apuntando lo que te cueste caro.
- `.claude/settings.json` con permisos: `deny` para `pct destroy`, `qm destroy`, `pvesm free`,
  `pct restore`, `qmrestore`, `pvecm delnode` y `rm -rf /*`, y `ask` para cada `ssh` y `scp`.
- `.claude/hooks/bloquear-destructivo.sh`, un hook que mira el comando entero antes de ejecutarlo,
  también lo que va dentro de `ssh nodo "..."`, y lo para si es destructivo.
- `scripts/homelab-actualizar`, un script para actualizar contenedores con copia previa,
  verificación y marcha atrás, con su timer de systemd.
- `docs/SEGURIDAD.md` y `docs/MANTENIMIENTO.md`: el porqué de todo esto.
- `ejemplos/vigilante/`: un agente de solo lectura que cuenta cada mañana cómo está el homelab,
  con una clave SSH que solo puede ejecutar cinco consultas.

## Cómo usarlo

1. Clona el repo y ábrelo con Claude Code. Necesitas `jq` para que funcione el hook; si falta,
   el hook bloquea todo en vez de dejar pasar.
2. Sustituye `nodo1`, `nodo2` y `nas` por los nombres de tus nodos y tu almacenamiento, y
   configura los alias en `~/.ssh/config` (hay un ejemplo en `CLAUDE.md`).
3. Copia `.env.example` a `.env` si vas a guardar variables. El `.env` no se sube a git.
4. Instala `homelab-actualizar` en los nodos siguiendo `docs/MANTENIMIENTO.md`. Antes de dejarlo
   en el timer, pruébalo con `plan`, luego con `guest <id> --simular` y, sobre un guest que no
   importe, con `--ensayo-fallo` para ver que la marcha atrás funciona.
5. Si quieres un vigilante de solo lectura, sigue `ejemplos/vigilante/README.md`.
6. Cada cosa que te cueste un rato, apúntala en la sección de trampas de `CLAUDE.md`.

## Cómo probar el hook

```
bash tests/probar-hook.sh
```

Pasa unos ochenta comandos de ejemplo al hook por stdin, sin tocar ningún nodo ni la red, e
imprime OK o FALLO por cada uno. Sale con código distinto de cero si alguno falla. Los casos
incluyen `pct destroy 101`, `ssh nodo2 "pct destroy 101"`, `rm -rf /` y el borrado de copias
`vzdump`, que se deben denegar, y otros como `pct list` o `rm -rf ./build`, que deben pasar.

Las otras dos baterías son `bash tests/probar-actualizar.sh` (el actualizador contra `pct` y `qm`
simulados) y `bash ejemplos/vigilante/tests/probar-lectura.sh` (el envoltorio del vigilante).

## Lo que no hace

El hook es una red de seguridad, no un intérprete de shell: no resuelve variables ni base64, y
puede bloquear de más. Un `deny` de Claude Code y un hook son capas distintas, y ninguna de las
dos sustituye a quitarle al agente los permisos que no necesita. `docs/SEGURIDAD.md` lo explica
con calma, junto a lo que no se automatiza a propósito (restaurar copias, Home Assistant OS,
imágenes de Docker con base de datos).

## Licencia

MIT, ver `LICENSE`.
