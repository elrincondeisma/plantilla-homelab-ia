#!/usr/bin/env bash
# parte.sh: el que corre el agente vigilante.
#
# Pregunta por ssh a cada nodo con la clave dedicada (solo lectura, ver
# homelab-lectura), junta el resultado en un texto corto y lo imprime por
# stdout. Quien lo ejecuta (Hermes Agent, cron...) se encarga de entregarlo.
#
# Variables (todas opcionales):
#   NODOS            nodos a consultar, separados por espacio   (nodo1 nodo2)
#   USUARIO          usuario ssh                                (root)
#   CLAVE_VIGILANTE  clave privada dedicada                     (~/.ssh/id_vigilante)
#   ALMACEN          el mismo que fija homelab-lectura          (nas)
#   UMBRAL_DISCO     % de uso a partir del cual se avisa        (85)

NODOS="${NODOS:-nodo1 nodo2}"
USUARIO="${USUARIO:-root}"
CLAVE_VIGILANTE="${CLAVE_VIGILANTE:-$HOME/.ssh/id_vigilante}"
ALMACEN="${ALMACEN:-nas}"
UMBRAL_DISCO="${UMBRAL_DISCO:-85}"

# Las órdenes se mandan tal cual, sin "export LC_ALL=C;" delante: el envoltorio
# solo acepta el texto exacto y ya fija el idioma él.
consulta() { # nodo orden...
  local nodo=$1; shift
  ssh -i "$CLAVE_VIGILANTE" -o BatchMode=yes -o IdentitiesOnly=yes \
      -o ConnectTimeout=10 -o StrictHostKeyChecking=yes \
      "$USUARIO@$nodo" "$*" 2>/dev/null
}

problemas=0
echo "Parte del homelab, $(date '+%F %H:%M')"

for nodo in $NODOS; do
  if ! cluster=$(consulta "$nodo" "pvecm status"); then
    echo "$nodo: NO RESPONDE"
    problemas=$((problemas + 1))
    continue
  fi
  linea="$nodo:"

  if echo "$cluster" | grep -q 'Quorate:.*Yes'; then
    linea="$linea cluster con quórum;"
  else
    linea="$linea CLUSTER SIN QUÓRUM;"
    problemas=$((problemas + 1))
  fi

  # Almacenamientos por encima del umbral (última columna de 'pvesm status' = %).
  llenos=$(consulta "$nodo" "pvesm status" | awk -v u="$UMBRAL_DISCO" \
    'NR>1 { p=$NF; sub(/%/,"",p); if (p+0 >= u) printf "%s %s%% ", $1, p }')
  if [ -n "$llenos" ]; then
    linea="$linea almacenamiento lleno: $llenos;"
    problemas=$((problemas + 1))
  else
    linea="$linea almacenamientos bien;"
  fi

  # Cuarentena del actualizador.
  cuarentena=$(consulta "$nodo" "homelab-actualizar cuarentena lista" | grep -v 'vacía')
  if [ -n "$cuarentena" ]; then
    linea="$linea en cuarentena: $(echo "$cuarentena" | awk '{printf "%s ", $1}');"
    problemas=$((problemas + 1))
  fi

  # Última ronda del actualizador.
  ultimo=$(consulta "$nodo" "homelab-actualizar estado" | tail -n 1)
  case "$ultimo" in
    *'"resultado":"ROTO"'*) linea="$linea ROTO en la última ronda;"; problemas=$((problemas + 1)) ;;
  esac

  echo "$linea"
done

# Copias: cuántas hay en el almacén (se pregunta al primer nodo que responda).
for nodo in $NODOS; do
  if lista=$(consulta "$nodo" "pvesm list $ALMACEN --content backup"); then
    copias=$(echo "$lista" | awk 'NR>1' | wc -l | tr -d ' ')
    echo "Copias en $ALMACEN: $copias"
    [ "$copias" -eq 0 ] && problemas=$((problemas + 1))
    break
  fi
done

if [ "$problemas" -eq 0 ]; then
  echo "Todo en orden."
else
  echo "Hay $problemas cosas que mirar."
fi
exit 0
