#!/usr/bin/env bash
# Prueba homelab-actualizar en local con pct, qm y vzdump simulados (stubs en PATH).
# No toca ningún nodo, ni la red, ni /etc, ni /var: todo el estado va a un
# directorio temporal.
#
# Uso: bash tests/probar-actualizar.sh      (código != 0 si algún caso falla)

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$DIR/scripts/homelab-actualizar"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

total=0
fallos=0

ok() { total=$((total + 1)); echo "OK     $1"; }
mal() { total=$((total + 1)); fallos=$((fallos + 1)); echo "FALLO  $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/         /'; }

# ----------------------------------------------------------------- los stubs
BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/pct" <<'EOF'
#!/usr/bin/env bash
echo "pct $*" >> "$STUB_LOG"
case "$1" in
  list)
    printf 'VMID       Status     Lock         Name\n'
    printf '101        running                 web\n'
    printf '102        running                 db\n'
    printf '103        stopped                 viejo\n'
    printf '104        running                 excluido\n'
    ;;
  status)
    case "$2" in
      101|102|104) echo "status: running" ;;
      103) echo "status: stopped" ;;
      *) exit 2 ;;
    esac
    ;;
  exec)
    id=$2
    todo="$*"
    case "$todo" in
      *HLA_DETECTAR*) echo apt ;;
      *HLA_REFRESCAR*) ;;
      *HLA_PENDIENTES*) echo 3 ;;
      *HLA_ACTUALIZAR*) exit "${STUB_ACT_RC:-0}" ;;
      *HLA_REINICIO*) echo no ;;
      *HLA_SONDA*)
        n=$(cat "$STUB_SONDA_DIR/$id.n" 2>/dev/null || echo 0)
        n=$((n + 1)); echo "$n" > "$STUB_SONDA_DIR/$id.n"
        f="$STUB_SONDA_DIR/$id.$n"; [ -e "$f" ] || f="$STUB_SONDA_DIR/$id.defecto"
        cat "$f"
        ;;
      *" -- true"*) ;;
    esac
    ;;
  snapshot|delsnapshot|rollback|stop|start|reboot) ;;
  *) exit 1 ;;
esac
exit 0
EOF

cat > "$BIN/qm" <<'EOF'
#!/usr/bin/env bash
echo "qm $*" >> "$STUB_LOG"
case "$1" in
  list)
    printf '      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID\n'
    printf '       200 haos                 running    4096              32.00 1234\n'
    ;;
  status) [ "$2" = "200" ] && echo "status: running" || exit 2 ;;
  *) exit 1 ;;
esac
EOF

cat > "$BIN/vzdump" <<'EOF'
#!/usr/bin/env bash
echo "vzdump $*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$BIN"/*

# ---------------------------------------------------------- entorno por caso
# nuevo_caso <nombre> : prepara un directorio limpio y la configuración
nuevo_caso() {
  CASO="$TMP/$1"
  mkdir -p "$CASO/sondas"
  : > "$CASO/llamadas.log"
  export STUB_LOG="$CASO/llamadas.log"
  export STUB_SONDA_DIR="$CASO/sondas"
  export STUB_ACT_RC=0
  export HOMELAB_ACTUALIZAR_CONF="$CASO/conf"
  export PATH="$BIN:$PATH_ORIGINAL"
  cat > "$CASO/conf" <<EOF
EXCLUIR="104"
DIR_ESTADO="$CASO/estado"
LOG="$CASO/log"
ESPERA_ARRANQUE=0
EOF
}
PATH_ORIGINAL=$PATH

# sonda <id> <n|defecto> <líneas...>
sonda() {
  local id=$1 n=$2; shift 2
  printf '%s\n' "$@" > "$STUB_SONDA_DIR/$id.$n"
}

# Una foto típica: servicio en 8080 (1F90) expuesto, y un puerto auxiliar
# aleatorio solo en localhost (C350 = 50000), como abre un servidor multimedia.
foto_base() { sonda "$1" "$2" "PUERTO 1F90 E" "PUERTO C350 L" "FIN"; }

llamo() { grep -qE "$1" "$STUB_LOG"; }

# ================================================================== casos

# 1. plan --simular: enseña lo que debe cada guest y no cambia nada
nuevo_caso plan
foto_base 101 defecto
salida=$(bash "$SCRIPT" plan --simular 2>&1); rc=$?
if [ $rc -eq 0 ] \
   && echo "$salida" | grep -E '^101 .*running.*apt +3 ' >/dev/null \
   && echo "$salida" | grep -E '^103 .*stopped.*parado' >/dev/null \
   && echo "$salida" | grep -E '^104 .*excluido' >/dev/null \
   && echo "$salida" | grep -E '^200 .*VM' >/dev/null \
   && ! llamo 'snapshot|rollback|vzdump|reboot|stop|start' \
   && [ ! -e "$CASO/estado" ]; then
  ok "plan --simular lista los guests y no cambia nada"
else
  mal "plan --simular" "$salida"
fi

# 2. guest --simular: cuenta lo que haría y no ejecuta nada que cambie
nuevo_caso simular
foto_base 101 defecto
salida=$(bash "$SCRIPT" guest 101 --simular 2>&1); rc=$?
if [ $rc -eq 0 ] \
   && echo "$salida" | grep -q '\[simular\] haría: snapshot' \
   && echo "$salida" | grep -q '\[simular\] haría: actualizar' \
   && ! llamo 'pct (snapshot|delsnapshot|rollback|stop|start|reboot)|vzdump' \
   && ! llamo 'HLA_ACTUALIZAR' \
   && [ ! -e "$CASO/estado" ] && [ ! -e "$CASO/log" ]; then
  ok "guest --simular enseña el ciclo y no toca nada (ni estado ni log)"
else
  mal "guest --simular" "$salida"
fi

# 3. Éxito: el puerto auxiliar de loopback desaparece y NO cuenta como fallo
nuevo_caso exito
foto_base 101 1
sonda 101 2 "PUERTO 1F90 E" "FIN"
salida=$(bash "$SCRIPT" guest 101 2>&1); rc=$?
if [ $rc -eq 0 ] \
   && echo "$salida" | grep -q 'actualizado y verificado' \
   && llamo 'pct snapshot 101 hla-' && llamo 'pct delsnapshot 101 hla-' \
   && ! llamo 'pct rollback' \
   && bash "$SCRIPT" cuarentena lista | grep -q 'vacía'; then
  ok "éxito: snapshot, actualización, verificación y borrado del snapshot; el puerto de loopback no da falso positivo"
else
  mal "éxito con puerto de loopback desaparecido" "$salida"
fi

# 4. Fallo real: desaparece un puerto expuesto -> rollback y cuarentena
nuevo_caso fallo
foto_base 101 1
sonda 101 2 "PUERTO C350 L" "FIN"
foto_base 101 3
salida=$(bash "$SCRIPT" guest 101 2>&1); rc=$?
if [ $rc -eq 1 ] \
   && echo "$salida" | grep -q 'el puerto 8080 ya no escucha' \
   && llamo 'pct rollback 101 hla-' \
   && bash "$SCRIPT" cuarentena lista | grep -q '^101 ' \
   && bash "$SCRIPT" guest 101 2>&1 | grep -q 'en cuarentena' \
   && bash "$SCRIPT" cuarentena quitar 101 >/dev/null \
   && bash "$SCRIPT" cuarentena lista | grep -q 'vacía'; then
  ok "fallo real: vuelve al snapshot, queda en cuarentena y se puede sacar"
else
  mal "fallo real" "$salida (rc=$rc)"
fi

# 5. --ensayo-fallo: finge el fallo, revierte, no deja cuarentena
nuevo_caso ensayo
foto_base 101 defecto
salida=$(bash "$SCRIPT" guest 101 --ensayo-fallo 2>&1); rc=$?
if [ $rc -eq 0 ] \
   && echo "$salida" | grep -q 'ensayo-fallo' \
   && llamo 'pct rollback 101 hla-' && llamo 'pct delsnapshot 101 hla-' \
   && bash "$SCRIPT" cuarentena lista | grep -q 'vacía'; then
  ok "--ensayo-fallo revierte al snapshot y no deja el guest en cuarentena"
else
  mal "--ensayo-fallo" "$salida (rc=$rc)"
fi

# 6. Puertos ignorados por guest en la configuración
nuevo_caso ignorados
echo 'PUERTOS_IGNORADOS="102:9090 *:7777"' >> "$CASO/conf"
sonda 102 1 "PUERTO 2382 E" "PUERTO 1E61 E" "FIN"      # 9090 y 7777
sonda 102 2 "FIN"
salida=$(bash "$SCRIPT" guest 102 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$salida" | grep -q 'actualizado y verificado'; then
  ok "los puertos de PUERTOS_IGNORADOS no cuentan en la verificación"
else
  mal "puertos ignorados" "$salida (rc=$rc)"
fi

# 6b. Lo mismo sin la lista: el puerto expuesto que desaparece sí es fallo
nuevo_caso sin_ignorados
sonda 102 1 "PUERTO 2382 E" "FIN"
sonda 102 2 "FIN"
sonda 102 3 "PUERTO 2382 E" "FIN"
bash "$SCRIPT" guest 102 >/dev/null 2>&1; rc=$?
if [ $rc -eq 1 ] && llamo 'pct rollback 102'; then
  ok "sin PUERTOS_IGNORADOS, un puerto expuesto que desaparece sí revierte"
else
  mal "puerto expuesto sin ignorar (rc=$rc)"
fi

# 6c. IGNORAR_LOOPBACK=0: el puerto de loopback pasa a contar
nuevo_caso loopback_cuenta
echo 'IGNORAR_LOOPBACK=0' >> "$CASO/conf"
foto_base 101 1
sonda 101 2 "PUERTO 1F90 E" "FIN"
foto_base 101 3
bash "$SCRIPT" guest 101 >/dev/null 2>&1; rc=$?
if [ $rc -eq 1 ] && llamo 'pct rollback 101'; then
  ok "con IGNORAR_LOOPBACK=0 el puerto de loopback vuelve a contar"
else
  mal "IGNORAR_LOOPBACK=0 (rc=$rc)"
fi

# 7. Guest sin snapshot: copia con vzdump y sin snapshot
nuevo_caso vzdump
echo 'SIN_SNAPSHOT="102"' >> "$CASO/conf"
echo 'ALMACEN_COPIAS="nas"' >> "$CASO/conf"
sonda 102 defecto "PUERTO 2382 E" "FIN"
salida=$(bash "$SCRIPT" guest 102 2>&1); rc=$?
if [ $rc -eq 0 ] && llamo 'vzdump 102 --storage nas' && ! llamo 'pct snapshot'; then
  ok "SIN_SNAPSHOT: copia previa con vzdump en el almacén configurado"
else
  mal "vzdump" "$salida (rc=$rc)"
fi

# 8. Excluido, parado y VM: no se tocan
nuevo_caso omitidos
r1=$(bash "$SCRIPT" guest 104 2>&1); r2=$(bash "$SCRIPT" guest 103 2>&1); r3=$(bash "$SCRIPT" guest 200 2>&1)
if echo "$r1" | grep -q 'excluido' && echo "$r2" | grep -q 'parado' && echo "$r3" | grep -q 'VM' \
   && ! llamo 'snapshot|vzdump|rollback'; then
  ok "excluido, parado y VM: se omiten sin tocar nada"
else
  mal "omitidos" "$r1 / $r2 / $r3"
fi

# 9. Ayuda y orden desconocida
nuevo_caso ayuda
if bash "$SCRIPT" ayuda | grep -q 'cuarentena' && ! bash "$SCRIPT" nada >/dev/null 2>&1; then
  ok "ayuda y orden desconocida (sale con error)"
else
  mal "ayuda"
fi

# 10. La sonda: filtra loopback de verdad (lee /proc/net/tcp y tcp6 simulados)
PROC="$TMP/proc"
mkdir -p "$PROC"
cat > "$PROC/tcp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1 1 0
   1: 0100007F:C350 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 2 1 0
   2: 0100007F:1234 0100007F:9999 01 00000000:00000000 00:00000000 00000000     0        0 3 1 0
   3: 0101A8C0:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4 1 0
EOF
cat > "$PROC/tcp6" <<'EOF'
  sl  local_address                         rem_address                            st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000000000000:0016 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 5 1 0
   1: 00000000000000000000000001000000:C351 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 6 1 0
   2: 0000000000000000FFFF00000100007F:C352 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 7 1 0
EOF
sal=$(bash "$SCRIPT" _sonda | HLA_PROC="$PROC" sh | grep '^PUERTO' | sort | tr '\n' '|')
esperado='PUERTO 0016 E|PUERTO 0050 E|PUERTO 1F90 E|PUERTO C350 L|PUERTO C351 L|PUERTO C352 L|'
if [ "$sal" = "$esperado" ]; then
  ok "la sonda marca como loopback 127.x, ::1 y ::ffff:127.x, y ignora lo que no está en LISTEN"
else
  mal "sonda sobre /proc simulado" "obtenido: $sal
esperado: $esperado"
fi

# 11. Configuración escribible por cualquiera: se rechaza
nuevo_caso conf_abierta
chmod 666 "$CASO/conf"
bash "$SCRIPT" estado >/dev/null 2>&1; rc=$?
chmod 600 "$CASO/conf"
if [ $rc -eq 2 ]; then ok "una configuración escribible por cualquiera se rechaza"; else mal "conf escribible (rc=$rc)"; fi

# 12. Sintaxis
if bash -n "$SCRIPT"; then ok "bash -n limpio"; else mal "bash -n"; fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S error "$SCRIPT"; then ok "shellcheck sin errores"; else mal "shellcheck"; fi
else
  echo "----   shellcheck no está instalado: no se ha pasado"
fi

echo
if [ "$fallos" -eq 0 ]; then echo "Todo en orden: $total casos."; exit 0; fi
echo "$fallos de $total casos han fallado."
exit 1
