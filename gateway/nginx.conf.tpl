# 템플릿: ${GRAFANA_UPSTREAM}, ${PROMETHEUS_UPSTREAM} 만 .env 값으로 치환됩니다.
# nginx 내장 변수($host 등)는 그대로 보존됩니다.
server {
    listen 80;
    server_name _;

    # 랜딩 포털 (정적)
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    # Grafana (서브패스 + 웹소켓/Live 지원)
    # 트레일링 슬래시 없음 → /grafana/ prefix 를 그대로 전달 (serve_from_sub_path=true 와 짝)
    location /grafana/ {
        proxy_pass http://${GRAFANA_UPSTREAM};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Prometheus (route-prefix=/prometheus/ 와 일치)
    location /prometheus/ {
        proxy_pass http://${PROMETHEUS_UPSTREAM}/prometheus/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 백엔드(Spring Boot) 헬스체크 — 포털 BACKEND 카드 전용.
    # ECS 태스크 IP 변동 대응: 변수+resolver 로 요청 시점에 DNS 재해석 (Docker 내장 DNS 127.0.0.11).
    location = /healthz/backend {
        resolver 127.0.0.11 valid=10s;
        set $backend_health "${PROM_TARGET}:${PROM_PORT}";
        proxy_pass http://$backend_health/actuator/health;
        proxy_set_header Host $host;
        proxy_connect_timeout 3s;
        proxy_read_timeout 3s;
    }

    # ── 새 도구 추가 시 여기에 location 한 블록 + portal/index.html 카드 한 줄 ──
    # location /pgadmin/ { proxy_pass http://pgadmin:80/; ... }
}
