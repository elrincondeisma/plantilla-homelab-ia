#!/usr/bin/env bash
# Hook PreToolUse (matcher Bash) de Claude Code.
#
# Lee por stdin el JSON de la llamada, saca .tool_input.command y lo analiza
# entero, incluido lo que va dentro de ssh host "...", bash -c '...', $(...),
# o encadenado con &&, ;, | y similares.
#
#   exit 0 sin salida  -> el comando pasa
#   exit 2 + stderr    -> el comando se bloquea y Claude recibe el mensaje
#
# Dependencias: bash y jq. Si falta jq, falla cerrado (exit 2).
#
# Cómo analiza: pasa el comando a minúsculas, parte por separadores de comando,
# quita comillas y barras invertidas (así "ssh n 'pct destroy 1'" queda a la
# vista) y mira palabra a palabra cada tramo. Es una red de seguridad, no un
# parser de shell: no resuelve variables, expansiones de llaves ni base64.
# Ante la duda, bloquea. Ver docs/SEGURIDAD.md.
#
# Compatible con bash 3.2 (macOS) y 5.x.

export LC_ALL=C

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOQUEADO por bloquear-destructivo.sh: falta 'jq' y el hook no puede analizar el comando. Falla cerrado a propósito. Instala jq (apt install jq / brew install jq) y reintenta." >&2
  exit 2
fi

entrada=$(cat)

if ! comando=$(printf '%s' "$entrada" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOQUEADO por bloquear-destructivo.sh: la entrada no es un JSON válido y no se puede analizar el comando. Falla cerrado a propósito." >&2
  exit 2
fi

# Sin comando (otra herramienta, o vacío): nada que revisar.
[ -n "$comando" ] || exit 0

# ---------------------------------------------------------------- denegar
denegar() {
  # $1 = qué se ha parado, $2 = cómo hacerlo a mano
  local corto
  corto=$(printf '%s' "$comando" | tr '\n' ' ' | cut -c1-300)
  {
    echo "BLOQUEADO por .claude/hooks/bloquear-destructivo.sh: $1."
    echo "Comando: $corto"
    echo "Esto es destructivo o irreversible y no se lanza desde el agente."
    echo "Si de verdad hay que hacerlo: $2"
    echo "Hazlo tú, a mano, desde una terminal propia (no desde el agente), después de comprobar que hay copia y que nada depende de ello."
  } >&2
  exit 2
}

# -------------------------------------------------------------- normalizar
norm=$(printf '%s' "$comando" | tr '[:upper:]' '[:lower:]' | tr '\r\t' '  ')
norm=${norm//\\$'\n'/ }              # continuación de línea
norm=${norm//\$\{ifs\}/ }
norm=${norm//\$ifs/ }
norm=${norm//\$\(/$'\n'}
norm=${norm//\`/$'\n'}
norm=${norm//\(/$'\n'}
norm=${norm//\)/$'\n'}
norm=${norm//;/$'\n'}
norm=${norm//|/$'\n'}
norm=${norm//&/$'\n'}
norm=${norm//\"/}
norm=${norm//\'/}
norm=${norm//\\/}
norm=${norm//\$/}

re_raiz='^/(\*|\.|\.\.)?/?\*?$'

while IFS= read -r tramo; do
  [ -n "${tramo// /}" ] || continue
  read -ra p <<< "$tramo"
  n=${#p[@]}
  [ "$n" -gt 0 ] || continue

  # Tramos que solo imprimen o buscan texto no ejecutan nada.
  primero=${p[0]##*/}
  case "$primero" in
    grep|egrep|fgrep|rg|echo|printf|man) continue ;;
  esac

  i=0
  while [ "$i" -lt "$n" ]; do
    t=${p[$i]}
    base=${t##*/}
    sig=""
    [ $((i + 1)) -lt "$n" ] && sig=${p[$((i + 1))]}

    case "$base" in
      pct)
        [ "$sig" = "destroy" ] && denegar "'pct destroy' (borra un contenedor y sus discos)" "pct destroy <id>  (añade --purge solo si quieres limpiar también copias y jobs)"
        ;;
      qm)
        [ "$sig" = "destroy" ] && denegar "'qm destroy' (borra una VM y sus discos)" "qm destroy <id>"
        ;;
      pvesm)
        [ "$sig" = "free" ] && denegar "'pvesm free' (borra un volumen del almacenamiento, copias incluidas)" "pvesm free <volid>  (comprueba antes con 'pvesm list <almacen>')"
        ;;
      pvecm)
        [ "$sig" = "delnode" ] && denegar "'pvecm delnode' (saca un nodo del cluster)" "pvecm delnode <nodo>  (el nodo debe estar apagado y no volver a la red sin reinstalar)"
        ;;
      mkfs|mkfs.*)
        denegar "'$base' (formatea un dispositivo)" "$base <dispositivo>  (comprueba con lsblk que es el disco que crees)"
        ;;
      dd)
        for x in "${p[@]}"; do
          case "$x" in
            of=/dev/null) ;;
            of=/dev/*) denegar "'dd' escribiendo en un dispositivo ($x)" "dd if=<origen> $x  (comprueba con lsblk que el destino es el correcto)" ;;
          esac
        done
        ;;
      rm|unlink|shred)
        # Primero las banderas (da igual que vayan detrás del objetivo).
        recursivo=0
        k=$((i + 1))
        while [ "$k" -lt "$n" ]; do
          a=${p[$k]}
          case "$a" in
            --recursive) recursivo=1 ;;
            --*) ;;
            -*) case "$a" in *r*) recursivo=1 ;; esac ;;
          esac
          k=$((k + 1))
        done
        # Después los objetivos.
        k=$((i + 1))
        while [ "$k" -lt "$n" ]; do
          a=${p[$k]}
          case "$a" in
            -*) ;;
            *)
              # Normaliza barras repetidas: ////  ->  /
              while [[ $a == *//* ]]; do a=${a//\/\//\/}; done
              if [ "$recursivo" -eq 1 ] && [[ $a =~ $re_raiz ]]; then
                denegar "borrado recursivo de la raíz del sistema ($base ... $a)" "rm -rf <ruta>  (con una ruta concreta, nunca la raíz)"
              fi
              case "$a" in
                *vzdump-*) denegar "borrado de una copia de seguridad vzdump ($a)" "rm <fichero>  o  pvesm free <volid>, tras comprobar que hay otra copia válida" ;;
              esac
              if [[ $a == /dump || $a == /dump/* || $a == */dump || $a == */dump/* ]] && [[ $a == /* ]]; then
                denegar "borrado dentro de un directorio de copias ($a)" "rm <fichero>, tras comprobar que hay otra copia válida"
              fi
              ;;
          esac
          k=$((k + 1))
        done
        ;;
      find)
        # find ... vzdump-... -delete / -exec rm
        resto=" ${p[*]} "
        case "$resto" in
          *vzdump-*)
            case "$resto" in
              *" -delete "*|*" rm "*|*" unlink "*) denegar "'find' que borra copias vzdump" "find ... -delete, tras comprobar que hay otra copia válida" ;;
            esac
            ;;
        esac
        ;;
    esac

    # Banderas sueltas, en cualquier posición.
    case "$t" in
      --purge|--purge=*) denegar "'--purge' (borra además todo lo asociado: copias, jobs, configuración)" "repite el comando con --purge desde tu terminal, sabiendo qué se lleva" ;;
    esac

    i=$((i + 1))
  done
done <<< "$norm"

exit 0
