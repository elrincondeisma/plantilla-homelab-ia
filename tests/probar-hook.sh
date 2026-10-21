#!/usr/bin/env bash
# Batería de pruebas del hook bloquear-destructivo.sh.
# Pasa JSON de ejemplo por stdin al hook. No toca ningún nodo ni la red:
# los comandos de los casos solo se analizan como texto, nunca se ejecutan.
#
# Uso: bash tests/probar-hook.sh        (sale con código != 0 si algún caso falla)

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$DIR/.claude/hooks/bloquear-destructivo.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "Hace falta jq para montar el JSON de los casos." >&2
  exit 1
fi

total=0
fallos=0

# caso <deniega|pasa> <comando>
caso() {
  local esperado=$1 comando=$2 json salida err rc
  total=$((total + 1))
  json=$(jq -cn --arg c "$comando" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')
  err=$(mktemp)
  salida=$(printf '%s' "$json" | bash "$HOOK" 2>"$err")
  rc=$?
  local msg; msg=$(cat "$err"); rm -f "$err"

  if [ "$esperado" = "deniega" ]; then
    if [ "$rc" -eq 2 ] && [ -n "$msg" ] && [ -z "$salida" ]; then
      echo "OK     deniega  $comando"
    else
      echo "FALLO  deniega  $comando   (rc=$rc, stderr vacío: $([ -z "$msg" ] && echo sí || echo no))"
      fallos=$((fallos + 1))
    fi
  else
    if [ "$rc" -eq 0 ] && [ -z "$msg" ] && [ -z "$salida" ]; then
      echo "OK     pasa     $comando"
    else
      echo "FALLO  pasa     $comando   (rc=$rc) $msg"
      fallos=$((fallos + 1))
    fi
  fi
}

echo "== Deben denegarse =="
caso deniega 'pct destroy 101'
caso deniega 'ssh nodo2 "pct destroy 101"'
caso deniega "ssh nodo2 'qm destroy 103 --purge'"
caso deniega 'ssh nodo1 "cd /tmp && pct destroy 101"'
caso deniega 'pvesm free nas:backup/vzdump-lxc-101-2026_01_01-03_00_00.tar.zst'
caso deniega 'rm -rf /'
caso deniega 'ssh nodo1 "rm -rf /mnt/pve/nas/dump/vzdump-lxc-101*"'
caso deniega 'ssh nodo1 "mkfs.ext4 /dev/sdb"'
caso deniega 'dd if=/dev/zero of=/dev/sda'
caso deniega "ssh nodo1 \"bash -c 'pct destroy 101'\""
# más variantes
caso deniega 'qm destroy 103'
caso deniega 'pct destroy 101 --purge'
caso deniega 'pct stop 101; pct destroy 101'
caso deniega 'pct list | head && pct destroy 101'
caso deniega 'ls || pct destroy 101'
caso deniega 'echo hola; qm destroy 9'
caso deniega 'ssh nodo1 "export LC_ALL=C; pct   destroy   101"'
caso deniega 'PCT DESTROY 101'
caso deniega 'pct	destroy 101'
caso deniega '/usr/sbin/pct destroy 101'
caso deniega 'sudo pct destroy 101'
caso deniega 'pct "destroy" 101'
caso deniega "p''ct destroy 101"
caso deniega 'pct\ destroy 101'
caso deniega 'bash -c "pct destroy 101"'
caso deniega 'sh -c "echo ok && qm destroy 9"'
caso deniega 'echo $(pct destroy 101)'
caso deniega 'echo `qm destroy 9`'
caso deniega $'pct stop 101\npct destroy 101'
caso deniega $'pct \\\ndestroy 101'
caso deniega 'pct${IFS}destroy 101'
caso deniega 'ssh nodo1 pct destroy 101'
caso deniega 'apt-get remove --purge foo'
caso deniega 'pvesm free local:backup/vzdump-qemu-103-2026_01_01-03_00_00.vma.zst'
caso deniega 'pvecm delnode nodo2'
caso deniega 'ssh nodo1 "pvecm delnode nodo2"'
caso deniega 'rm -fr /'
caso deniega 'rm -r -f /'
caso deniega 'rm -rf /*'
caso deniega 'rm -rf //'
caso deniega 'rm / -rf'
caso deniega 'rm --recursive --force /'
caso deniega 'rm -rf --no-preserve-root /'
caso deniega 'ssh nodo1 "rm -rf /"'
caso deniega 'rm /mnt/pve/nas/dump/vzdump-lxc-101-2026_01_01-03_00_00.tar.zst'
caso deniega 'rm -rf /var/lib/vz/dump/*'
caso deniega 'ssh nodo1 "find /mnt/pve/nas/dump -name vzdump-* -delete"'
caso deniega 'mkfs.ext4 /dev/sdb1'
caso deniega 'mkfs -t ext4 /dev/sdb'
caso deniega 'sudo /sbin/mkfs.xfs /dev/sdc'
caso deniega 'dd if=imagen.iso of=/dev/sdb bs=4M'
caso deniega 'ssh nodo1 "dd if=/dev/zero of=/dev/sda"'

echo
echo "== Deben pasar =="
caso pasa 'pct list'
caso pasa 'ssh nodo1 "pvesm status"'
caso pasa 'ssh nodo1 "export LC_ALL=C; pvesh get /cluster/resources --type vm"'
caso pasa 'rm -rf ./build'
caso pasa 'grep destroy notas.txt'
caso pasa 'ls /var/lib/vz/dump'
# más casos útiles
caso pasa 'pct status 101'
caso pasa 'pct config 101'
caso pasa 'qm list'
caso pasa 'pct snapshot 101 antes-de-actualizar'
caso pasa 'ssh nodo1 "pct exec 101 -- apt-get update"'
caso pasa 'pvesm list nas --content backup'
caso pasa 'pvecm status'
caso pasa 'ls -l /mnt/pve/nas/dump'
caso pasa 'ls /mnt/pve/nas/dump/vzdump-lxc-101*'
caso pasa 'rm -rf /tmp/prueba'
caso pasa 'rm fichero.txt'
caso pasa 'rm -r ./node_modules'
caso pasa 'rm -rf build dist'
caso pasa 'dd if=/dev/zero of=./relleno.img bs=1M count=1'
caso pasa 'dd if=/dev/sda of=/dev/null bs=1M count=10'
caso pasa 'echo "para destruir: pct destroy <id>"'
caso pasa 'grep -rn "qm destroy" docs/'
caso pasa 'cat docs/SEGURIDAD.md | grep pvesm'
caso pasa 'scp nodo1:/etc/pve/storage.cfg ./storage.cfg'
caso pasa 'systemctl status homelab-actualizar.timer'
caso pasa 'homelab-actualizar plan --simular'
caso pasa 'cd /tmp && ls && pwd'
caso pasa 'git status'

echo
echo "== Entradas especiales =="

# Otra herramienta distinta de Bash (sin tool_input.command): pasa.
total=$((total + 1))
if printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/etc/hostname"}}' | bash "$HOOK" >/dev/null 2>&1; then
  echo "OK     pasa     entrada sin tool_input.command"
else
  echo "FALLO  pasa     entrada sin tool_input.command"; fallos=$((fallos + 1))
fi

# JSON roto: falla cerrado.
total=$((total + 1))
printf '%s' 'esto no es json' | bash "$HOOK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "OK     deniega  JSON inválido (falla cerrado)"
else
  echo "FALLO  deniega  JSON inválido (rc=$rc)"; fallos=$((fallos + 1))
fi

# Sin jq: falla cerrado con exit 2 y mensaje. Se simula con un PATH vacío.
total=$((total + 1))
vacio=$(mktemp -d)
err=$(printf '%s' '{"tool_input":{"command":"pct list"}}' | PATH="$vacio" /bin/bash "$HOOK" 2>&1 >/dev/null)
rc=$?
rmdir "$vacio"
if [ "$rc" -eq 2 ] && [ -n "$err" ]; then
  echo "OK     deniega  falta jq (falla cerrado)"
else
  echo "FALLO  deniega  falta jq (rc=$rc)"; fallos=$((fallos + 1))
fi

echo
if [ "$fallos" -eq 0 ]; then
  echo "Todo en orden: $total casos."
  exit 0
fi
echo "$fallos de $total casos han fallado."
exit 1
