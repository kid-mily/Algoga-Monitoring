# 이 파일은 템플릿입니다. 컨테이너 기동 시 .env 값이 주입되어
# /rendered/prometheus.yml 로 렌더링됩니다. (직접 수정하지 말고 .env 를 바꾸세요)
global:
  scrape_interval: ${SCRAPE_INTERVAL}

scrape_configs:
  # 백엔드(Spring Boot) 메트릭.
  # ECS Cloud Map DNS(A레코드=태스크 IP들)를 dns_sd로 자동 추적 → 태스크 IP가 바뀌어도 OK.
  - job_name: 'algoga-backend'
    metrics_path: '${PROM_PATH}'
    dns_sd_configs:
      - names: ['${PROM_TARGET}']
        type: 'A'
        port: ${PROM_PORT}

  # (선택) Cloud Map 없이 정적 주소/내부 ALB로 긁고 싶으면 위 dns_sd 대신 아래 사용:
  # static_configs:
  #   - targets: ['${PROM_TARGET}:${PROM_PORT}']
