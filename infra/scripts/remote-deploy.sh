#!/usr/bin/env bash
set -euo pipefail

JAR_URI="${JAR_URI:?JAR_URI not set}"
SECRET_NAME="${SECRET_NAME:?SECRET_NAME not set}"
APP_PORT="${APP_PORT:-2330}"
VERSION="${VERSION:-unknown}"
REGION="${AWS_REGION:-us-east-1}"
APP_DIR=/opt/bizapp

echo "Deploying ${VERSION}"

# Keep the previous jar so rollback is a file move, not a rebuild
if [ -f "${APP_DIR}/app.jar" ]; then
  cp "${APP_DIR}/app.jar" "${APP_DIR}/app.jar.previous"
fi

aws s3 cp "${JAR_URI}" "${APP_DIR}/app.jar" --region "${REGION}"
chown appuser:appuser "${APP_DIR}/app.jar"

# Credentials are read at start time, never baked into the artifact
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_NAME}" --region "${REGION}" \
  --query SecretString --output text)

DB_HOST=$(echo "${SECRET}" | jq -r .host)
DB_PORT=$(echo "${SECRET}" | jq -r .port)
DB_NAME=$(echo "${SECRET}" | jq -r .dbname)
DB_USER=$(echo "${SECRET}" | jq -r .username)
DB_PASS=$(echo "${SECRET}" | jq -r .password)

# Credentials live in the unit file (root-readable only), not on the
# command line where they would show up in ps output
cat > /etc/systemd/system/bizapp.service <<UNIT
[Unit]
Description=Business Management application
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=${APP_DIR}
Environment="SPRING_DATASOURCE_URL=jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
Environment="SPRING_DATASOURCE_USERNAME=${DB_USER}"
Environment="SPRING_DATASOURCE_PASSWORD=${DB_PASS}"
Environment="SERVER_PORT=${APP_PORT}"
Environment="APP_VERSION=${VERSION}"
ExecStart=/usr/bin/java -jar ${APP_DIR}/app.jar
SuccessExitStatus=143
Restart=on-failure
RestartSec=5
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
UNIT

chmod 600 /etc/systemd/system/bizapp.service

systemctl daemon-reload
systemctl enable bizapp
systemctl restart bizapp

# Wait for readiness before reporting success
for i in $(seq 1 40); do
  if curl -sf "http://localhost:${APP_PORT}/actuator/health" >/dev/null 2>&1; then
    echo "Healthy after $((i * 3))s"
    exit 0
  fi
  sleep 3
done

echo "Failed to become healthy"
journalctl -u bizapp -n 50 --no-pager
exit 1