#!/usr/bin/env bash
# Prueba el envoltorio homelab-lectura en local, con SSH_ORIGINAL_COMMAND
# simulado. Se hace una copia del envoltorio con las rutas de los binarios
# apuntando a stubs, así que no se ejecuta nada real ni se toca la red.
#
# Uso: bash ejemplos/vigilante/tests/probar-lectura.sh   (código != 0 si algo falla)

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ORIGINAL="$DIR/homelab-lectura"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Stub genérico: anota quién lo llamó y con qué argumentos.
stub() {
  cat > "$1" <<EOF
#!/bin/sh
echo "\$(basename "\$0") \$*" >> "$TMP/llamadas"
echo "salida-del-stub"
EOF
  chmod +x "$1"
}
stub "$TMP/homelab-actualizar"
stub "$TMP/pvesm"
stub "$TMP/pvecm"
cat > "$TMP/logger" <<EOF
#!/bin/sh
echo "\$*" >> "$TMP/syslog"
EOF
chmod +x "$TMP/logger"

# Copia del envoltorio con las rutas de los binarios cambiadas.
sed -e "s|^BIN_ACTUALIZAR=.*|BIN_ACTUALIZAR=$TMP/homelab-actualizar|" \
    -e "s|^BIN_PVESM=.*|BIN_PVESM=$TMP/pvesm|" \
    -e "s|^BIN_PVECM=.*|BIN_PVECM=$TMP/pvecm|" \
    -e "s|^BIN_LOGGER=.*|BIN_LOGGER=$TMP/logger|" \
    "$ORIGINAL" > "$TMP/homelab-lectura"
chmod +x "$TMP/homelab-lectura"

for v in BIN_ACTUALIZAR BIN_PVESM BIN_PVECM BIN_LOGGER; do
  if ! grep -q "^$v=$TMP" "$TMP/homelab-lectura"; then
    echo "FALLO  no se pudo preparar la copia de prueba ($v)"; exit 1
  fi
done

total=0
fallos=0

# permitido <orden> <llamada esperada al stub>
permitido() {
  total=$((total + 1))
  : > "$TMP/llamadas"
  local salida rc
  salida=$(SSH_ORIGINAL_COMMAND="$1" bash "$TMP/homelab-lectura" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && [ "$(cat "$TMP/llamadas")" = "$2" ]; then
    echo "OK     permite  [$1]"
  else
    echo "FALLO  permite  [$1]  (rc=$rc, llamadas: $(cat "$TMP/llamadas"))"
    fallos=$((fallos + 1))
  fi
}

# rechazado <orden>
rechazado() {
  total=$((total + 1))
  : > "$TMP/llamadas"; : > "$TMP/syslog"
  local salida rc
  salida=$(SSH_ORIGINAL_COMMAND="$1" bash "$TMP/homelab-lectura" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$TMP/llamadas" ] && [ -s "$TMP/syslog" ]; then
    echo "OK     rechaza  [$1]"
  else
    echo "FALLO  rechaza  [$1]  (rc=$rc, llamadas: $(cat "$TMP/llamadas"), syslog: $(cat "$TMP/syslog"))"
    fallos=$((fallos + 1))
  fi
}

echo "== Permitidos =="
permitido 'homelab-actualizar estado'            'homelab-actualizar estado'
permitido 'homelab-actualizar cuarentena lista'  'homelab-actualizar cuarentena lista'
permitido 'pvesm status'                         'pvesm status'
permitido 'pvecm status'                         'pvecm status'
permitido 'pvesm list nas --content backup'      'pvesm list nas --content backup'

echo
echo "== Rechazados =="
rechazado 'pct list'
rechazado 'pct destroy 99999'
rechazado 'bash'
rechazado 'homelab-actualizar estado; rm -rf /'
rechazado 'pvesm status && id'
rechazado ''
# más
rechazado 'homelab-actualizar estado '
rechazado ' pvesm status'
rechazado 'pvesm  status'
rechazado 'PVESM STATUS'
rechazado 'homelab-actualizar plan'
rechazado 'homelab-actualizar guest 101'
rechazado 'homelab-actualizar cuarentena quitar 101'
rechazado 'pvesm list otro --content backup'
rechazado 'pvesm list nas --content iso'
rechazado 'pvesm list nas --content backup; id'
rechazado 'pvesm list nas --content backup | sh'
rechazado 'pvesm status $(id)'
rechazado 'pvesm status `id`'
rechazado 'pvesm status > /tmp/x'
rechazado 'export LC_ALL=C; pvesm status'
rechazado $'pvesm status\nid'
rechazado 'pvesm free nas:backup/vzdump-lxc-101.tar.zst'
rechazado 'scp -t /tmp'
rechazado 'sh -c id'
rechazado 'pvecm status; id'
rechazado '/usr/sbin/pvesm status'

# Sin SSH_ORIGINAL_COMMAND (sesión interactiva): rechaza.
total=$((total + 1)); : > "$TMP/syslog"
if (unset SSH_ORIGINAL_COMMAND; bash "$TMP/homelab-lectura" >/dev/null 2>&1); then
  echo "FALLO  rechaza  sesión sin SSH_ORIGINAL_COMMAND"; fallos=$((fallos + 1))
else
  echo "OK     rechaza  sesión sin SSH_ORIGINAL_COMMAND"
fi

# El script no usa eval ni lanza shells con lo que manda el cliente.
total=$((total + 1))
if grep -vE '^\s*#' "$ORIGINAL" | grep -qE '\beval\b|\bsh -c\b|bash -c|\$\(\s*"?\$orden|`\$orden'; then
  echo "FALLO  el envoltorio contiene eval o pasa la orden a una shell"; fallos=$((fallos + 1))
else
  echo "OK     sin eval ni shell sobre la orden recibida"
fi

echo
if [ "$fallos" -eq 0 ]; then echo "Todo en orden: $total casos."; exit 0; fi
echo "$fallos de $total casos han fallado."
exit 1
