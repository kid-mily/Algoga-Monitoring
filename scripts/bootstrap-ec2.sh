#!/usr/bin/env bash
# 모니터링 EC2(Amazon Linux 2023) 부트스트랩: Docker + compose 설치 후 스택 기동
set -euo pipefail

echo "[1/4] Docker 설치"
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user || true

echo "[2/4] docker compose 플러그인 설치"
DOCKER_CONFIG=/usr/local/lib/docker
sudo mkdir -p "$DOCKER_CONFIG/cli-plugins"
sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
sudo chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"

echo "[3/4] .env 준비"
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "  .env 를 생성했습니다. 값(특히 PROM_TARGET, GF_ADMIN_PW)을 채운 뒤 다시 실행하세요."
  exit 0
fi

echo "[4/4] 스택 기동"
sudo docker compose up -d
echo "완료. 포털: http://<이 인스턴스>:${GATEWAY_PORT:-80}/  (SSM 포워딩 권장)"
