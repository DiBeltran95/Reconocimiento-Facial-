#!/usr/bin/env bash
# Asegura el modelo MobileFaceNet en app/assets/modelos/ antes de compilar.
# Prioridad: archivo ya presente en el repositorio → URL (entrada del workflow
# o secreto MODELO_TFLITE_URL). Sin modelo la app compila, pero el kiosco
# mostrará "Falta el modelo de reconocimiento".
set -euo pipefail

destino="assets/modelos/mobilefacenet.tflite"

if [ -f "$destino" ]; then
  echo "Modelo incluido en el repositorio ($(wc -c < "$destino") bytes)."
  exit 0
fi

if [ -n "${MODELO_URL:-}" ]; then
  curl -fsSL --retry 3 "$MODELO_URL" -o "$destino"
  tamano=$(wc -c < "$destino")
  if [ "$tamano" -lt 1000000 ]; then
    echo "::error title=Modelo inválido::El archivo descargado pesa $tamano bytes; revisa que la URL sea la descarga directa del .tflite."
    exit 1
  fi
  echo "Modelo descargado ($tamano bytes)."
else
  echo "::warning title=Falta el modelo facial::No hay app/assets/modelos/mobilefacenet.tflite ni URL. La app se compila, pero no podrá reconocer rostros hasta incluirlo (ver README)."
fi
