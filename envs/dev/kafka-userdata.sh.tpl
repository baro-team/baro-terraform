#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1
echo "[$(date -u)] user-data START"

dnf update -y
dnf install -y docker

# dnf update 후 amazon-ssm-agent 유닛 파일이 사라질 수 있으므로 명시적 재설치
dnf install -y amazon-ssm-agent
systemctl daemon-reload
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent || true

systemctl enable --now docker

# Docker daemon 준비 대기 (최대 120초)
RETRY_COUNT=0
until docker info >/dev/null 2>&1; do
  if [ $RETRY_COUNT -eq 120 ]; then
    echo "Docker daemon failed to start after 120 seconds. Exiting."
    exit 1
  fi
  echo "Waiting for Docker daemon..."
  sleep 1
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

# EBS 볼륨이 비동기로 붙으므로 디바이스가 준비될 때까지 대기 (최대 300초)
RETRY_COUNT=0
while [ ! -b /dev/nvme1n1 ]; do
  if [ $RETRY_COUNT -eq 60 ]; then
    echo "EBS volume /dev/nvme1n1 not attached after 300 seconds. Exiting."
    exit 1
  fi
  echo "Waiting for /dev/nvme1n1 to be attached..."
  sleep 5
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if ! blkid /dev/nvme1n1; then
  mkfs.ext4 /dev/nvme1n1
fi
mkdir -p /var/kafka-data
mount | grep -q '/var/kafka-data' || mount /dev/nvme1n1 /var/kafka-data
if ! grep -q '/var/kafka-data' /etc/fstab; then
  echo '/dev/nvme1n1 /var/kafka-data ext4 defaults,nofail 0 2' >> /etc/fstab
fi
mkdir -p /var/kafka-data/kafka
chown 1000:1000 /var/kafka-data/kafka

echo "[$(date -u)] Logging into ECR"
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin ${ecr_url}

docker rm -f node-exporter || true
docker run -d --name node-exporter --restart unless-stopped \
  --pid host \
  -p 9100:9100 \
  -v /:/host:ro,rslave \
  quay.io/prometheus/node-exporter:v1.8.2 \
  --path.rootfs=/host

echo "[$(date -u)] Setting up JMX exporter"
mkdir -p /opt/kafka-jmx
cat <<'KAFKA_JMX_CONFIG' > /opt/kafka-jmx/kafka-jmx.yml
lowercaseOutputName: true
lowercaseOutputLabelNames: true
rules:
  - pattern: 'kafka.server<type=BrokerTopicMetrics, name=(BytesInPerSec|BytesOutPerSec|MessagesInPerSec), topic=(.+)><>Count'
    name: kafka_server_brokertopicmetrics_$1_total
    labels:
      topic: "$2"
    type: COUNTER
  - pattern: 'kafka.server<type=BrokerTopicMetrics, name=(BytesInPerSec|BytesOutPerSec|MessagesInPerSec)><>Count'
    name: kafka_server_brokertopicmetrics_$1_total
    labels:
      topic: all
    type: COUNTER
  - pattern: 'kafka.network<type=RequestMetrics, name=(RequestsPerSec|TotalTimeMs|RequestQueueTimeMs|ResponseQueueTimeMs|ResponseSendTimeMs), request=(Produce|FetchConsumer)><>Count'
    name: kafka_network_requestmetrics_$1_total
    labels:
      request: "$2"
    type: COUNTER
  - pattern: 'kafka.server<type=ReplicaManager, name=(UnderReplicatedPartitions|OfflineReplicaCount)><>Value'
    name: kafka_server_replicamanager_$1
    type: GAUGE
  - pattern: 'kafka.server<type=KafkaRequestHandlerPool, name=RequestHandlerAvgIdlePercent><>OneMinuteRate'
    name: kafka_server_kafkarequesthandlerpool_requesthandleravgidlepercent
    type: GAUGE
KAFKA_JMX_CONFIG
curl --fail --location --retry 3 --retry-delay 5 \
  --output /opt/kafka-jmx/jmx_prometheus_javaagent.jar \
  https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/1.0.1/jmx_prometheus_javaagent-1.0.1.jar
chown -R 1000:1000 /opt/kafka-jmx

echo "[$(date -u)] Starting Kafka container"
docker rm -f kafka || true
docker run -d --name kafka --restart unless-stopped \
  --entrypoint /etc/confluent/docker/run \
  -p 9092:9092 \
  -p 9093:9093 \
  -p 9404:9404 \
  -v /var/kafka-data/kafka:/var/kafka-data \
  -v /opt/kafka-jmx:/opt/kafka-jmx:ro \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka.${dns_namespace}:9092 \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT \
  -e KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  -e CLUSTER_ID=MkU3OEVBNTcwNTJENDM2Qk \
  -e KAFKA_LOG_DIRS=/var/kafka-data \
  -e KAFKA_HEAP_OPTS="-Xms256M -Xmx512M" \
  -e KAFKA_LOG_RETENTION_MS=3600000 \
  -e KAFKA_LOG_RETENTION_BYTES=268435456 \
  -e KAFKA_LOG_SEGMENT_MS=60000 \
  -e KAFKA_OPTS="-javaagent:/opt/kafka-jmx/jmx_prometheus_javaagent.jar=9404:/opt/kafka-jmx/kafka-jmx.yml" \
  ${ecr_url}:${image_tag}

echo "[$(date -u)] Waiting for Kafka to be ready..."
RETRY_COUNT=0
until docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1; do
  if [ $RETRY_COUNT -eq 30 ]; then
    echo "Kafka failed to start after 150 seconds. Exiting."
    exit 1
  fi
  sleep 5
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

echo "[$(date -u)] Ensuring vehicle-data-topic has 4 partitions..."
CURRENT_PARTS=$(docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --describe --topic vehicle-data-topic 2>/dev/null | grep -c "Partition:" || true)
if [ "$${CURRENT_PARTS:-0}" -eq 0 ]; then
  docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
    --create --topic vehicle-data-topic --partitions 4 --replication-factor 1 \
    --config retention.ms=3600000 \
    --config retention.bytes=268435456 \
    --config segment.ms=60000
elif [ "$${CURRENT_PARTS:-0}" -lt 4 ]; then
  docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
    --alter --topic vehicle-data-topic --partitions 4
fi
docker exec kafka kafka-configs --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name vehicle-data-topic \
  --alter --add-config retention.ms=3600000,retention.bytes=268435456,segment.ms=60000

echo "[$(date -u)] vehicle-data-topic ready (partitions=$${CURRENT_PARTS:-created})"
echo "[$(date -u)] user-data DONE"
