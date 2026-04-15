#!/usr/bin/env bash

set -euo pipefail

APP_USER="${APP_USER:-opc}"
APP_GROUP="${APP_GROUP:-$APP_USER}"
APP_DIR="${APP_DIR:-/opt/pero/backend}"
SERVICE_NAME="${SERVICE_NAME:-pero-backend}"
APP_JAR_SOURCE="${APP_JAR_SOURCE:-/tmp/pero-backend.jar}"
SERVICE_TEMPLATE_SOURCE="${SERVICE_TEMPLATE_SOURCE:-/tmp/pero-backend.service.template}"
ENV_FILE_SOURCE="${ENV_FILE_SOURCE:-/tmp/pero-backend.env.example}"
ENV_FILE_DEST="${ENV_FILE_DEST:-/etc/pero/pero-backend.env}"
APP_HEALTHCHECK_URL="${APP_HEALTHCHECK_URL:-http://127.0.0.1:8080/api/health}"

if [[ ! -f "$APP_JAR_SOURCE" ]]; then
  echo "missing jar: $APP_JAR_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$SERVICE_TEMPLATE_SOURCE" ]]; then
  echo "missing systemd template: $SERVICE_TEMPLATE_SOURCE" >&2
  exit 1
fi

sudo mkdir -p "$APP_DIR"
sudo mkdir -p "$(dirname "$ENV_FILE_DEST")"

if [[ ! -f "$ENV_FILE_DEST" ]]; then
  if [[ -f "$ENV_FILE_SOURCE" ]]; then
    sudo install -m 640 "$ENV_FILE_SOURCE" "$ENV_FILE_DEST"
  else
    sudo touch "$ENV_FILE_DEST"
    sudo chmod 640 "$ENV_FILE_DEST"
  fi
fi

RENDERED_SERVICE="$(mktemp)"
sed \
  -e "s|__APP_USER__|$APP_USER|g" \
  -e "s|__APP_GROUP__|$APP_GROUP|g" \
  -e "s|__APP_DIR__|$APP_DIR|g" \
  -e "s|__ENV_FILE__|$ENV_FILE_DEST|g" \
  "$SERVICE_TEMPLATE_SOURCE" > "$RENDERED_SERVICE"

sudo install -m 644 "$RENDERED_SERVICE" "/etc/systemd/system/${SERVICE_NAME}.service"
rm -f "$RENDERED_SERVICE"

sudo install -m 644 "$APP_JAR_SOURCE" "${APP_DIR}/app.jar"
sudo chown "$APP_USER:$APP_GROUP" "${APP_DIR}/app.jar"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

if command -v curl >/dev/null 2>&1; then
  for _ in $(seq 1 20); do
    if curl -fsS "$APP_HEALTHCHECK_URL" >/dev/null; then
      sudo systemctl --no-pager --full status "$SERVICE_NAME"
      exit 0
    fi
    sleep 2
  done
fi

sudo systemctl --no-pager --full status "$SERVICE_NAME"
echo "health check failed: $APP_HEALTHCHECK_URL" >&2
exit 1
