#!/bin/bash
set -euo pipefail
exec > /var/log/user-data.log 2>&1
echo "[$(date -u)] user-data START"

dnf update -y
dnf install -y docker
systemctl enable --now docker

systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent

docker network inspect baro-edge-net >/dev/null 2>&1 || docker network create baro-edge-net

echo "[$(date -u)] Fetching MQTT credentials"
MQTT_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "${region}" \
  --query SecretString \
  --output text)
MQTT_USER=$(echo "$MQTT_SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
MQTT_PASS=$(echo "$MQTT_SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

mkdir -p /opt/mosquitto/config /opt/mosquitto/data

cat > /opt/mosquitto/config/mosquitto.conf <<'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_type error
log_type warning
log_type notice
EOF

echo "[$(date -u)] Creating mosquitto passwd file"
printf "%s\n%s\n" "$MQTT_PASS" "$MQTT_PASS" | docker run --rm -i \
  -v /opt/mosquitto/config:/etc/mosquitto \
  eclipse-mosquitto:2 \
  mosquitto_passwd -c /etc/mosquitto/passwd "$MQTT_USER"

chmod 600 /opt/mosquitto/config/passwd

echo "[$(date -u)] Starting mosquitto container"
docker rm -f mosquitto || true
docker run -d --name mosquitto \
  --network baro-edge-net \
  --restart unless-stopped \
  -p 1883:1883 \
  -v /opt/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
  -v /opt/mosquitto/config/passwd:/mosquitto/config/passwd \
  -v /opt/mosquitto/data:/mosquitto/data \
  eclipse-mosquitto:2

echo "[$(date -u)] user-data DONE"
