# algoga-monitoring

개발팀 전용 **내부 운영 포털 + 관측 스택**. EC2 한 대에 Docker로 띄운다.

- **게이트웨이(Nginx)** 만 외부에 노출 → 랜딩 포털(`/`) + 리버스 프록시
- **Grafana / Prometheus / Loki** 는 내부 전용 (게이트웨이를 통해서만 접근)
- 바라보는 **주소·포트는 전부 `.env`** 로 설정 (컨테이너 기동 시 템플릿에 주입)

```
[개발팀] ──(SSM 포워딩 / ALB)──▶ EC2:GATEWAY_PORT (nginx)
                                   ├─ /            → 포털(index.html)
                                   ├─ /grafana/    → grafana:3000
                                   └─ /prometheus/ → prometheus:9090
   Prometheus ──(pull, dns_sd)──▶ ECS 백엔드 태스크 /actuator/prometheus
   ECS 앱     ──(push)─────────▶ Loki :3100 (로그)
```

## 폴더 구조
```
algoga-monitoring/
├── docker-compose.yml
├── .env.example              # cp .env.example .env 후 값 채우기 (.env 는 커밋 금지)
├── gateway/
│   ├── nginx.conf.tpl        # 리버스 프록시 (업스트림만 env 치환)
│   └── portal/index.html     # 랜딩 포털 (라이브 상태 표시)
├── prometheus/
│   └── prometheus.yml.tpl    # scrape 대상 env 치환 (Cloud Map dns_sd)
├── loki/loki-config.yml
├── grafana/
│   ├── provisioning/{datasources,dashboards,alerting}/
│   └── dashboards/*.json      # ← 대시보드 JSON 여기에 복사
└── scripts/bootstrap-ec2.sh
```

## 1. 대시보드 이관 (최초 1회)
기존 앱 레포의 대시보드/알림을 이 레포로 복사:
```bash
cp <앱레포>/monitoring/grafana/dashboards/*.json          grafana/dashboards/
cp <앱레포>/monitoring/grafana/provisioning/alerting/*.yaml grafana/provisioning/alerting/
```

## 2. 사전 준비 (AWS)
- **모니터링 EC2** 를 앱과 **같은 VPC** 에 생성 (SSM Agent + `AmazonSSMManagedInstanceCore` IAM 롤 권장)
- **ECS 백엔드 서비스에 Service Discovery(Cloud Map)** 활성화 → DNS 예: `backend.algoga.local`
- **보안 그룹**
  | 방향 | 포트 | 용도 |
  |---|---|---|
  | 모니터링EC2 → 백엔드 태스크 | 15000 | Prometheus 스크레이프 |
  | 앱 태스크 → 모니터링EC2 | 3100 | Loki 로그 push |
  | (SSM 접근이면 인바운드 불필요) | — | 포털은 SSM 포워딩 권장 |

## 3. 설정
```bash
cp .env.example .env
# .env 에서 최소: PROM_TARGET(=Cloud Map DNS), PROM_PORT, GF_ADMIN_PW 채우기
```

## 4. 배포 (EC2에서 Docker)
```bash
# 최초: 도커/컴포즈 설치 + 기동
bash scripts/bootstrap-ec2.sh      # .env 없으면 생성만 하고 멈춤 → 값 채우고 재실행

# 이후 일반 기동/갱신
docker compose up -d
docker compose logs -f gateway
```
- 자동 시작 원하면 systemd 유닛으로 감싸거나 `restart: unless-stopped`(이미 설정됨) + Docker 서비스 enable.

## 5. 접속 (개발팀)
공개 노출 없이 **SSM 포트포워딩** 권장:
```bash
aws ssm start-session --target <ec2-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
# → 브라우저 http://localhost:8080
```
(상시 URL이 필요하면 기존 ALB에 `ops.algoga.kro.kr` → EC2:GATEWAY_PORT host 규칙 추가 + 인증)

## 6. 로그 파이프라인 (앱 측, ECS)
로그는 앱이 Loki로 **push** 한다. ECS는 stdout이므로 **FireLens(Fluent Bit) 사이드카**에서 Loki로 출력:
```
[OUTPUT]
    Name   loki
    Match  *
    host   <모니터링EC2 사설IP 또는 Cloud Map DNS>
    port   3100
    labels job=algoga-backend
```
(이 설정은 **앱 레포/ECS 태스크 정의** 쪽에 둔다 — 로그 생산자 책임)

## 7. 도구 추가
1. `gateway/nginx.conf.tpl` 에 `location /xxx/ { proxy_pass http://컨테이너:포트/; }`
2. `gateway/portal/index.html` 에 카드 한 장
3. (컨테이너면) `docker-compose.yml` 에 서비스 추가

## 환경변수
| 변수 | 기본값 | 설명 |
|---|---|---|
| `GATEWAY_PORT` | 80 | 포털 노출 포트(호스트) |
| `PROM_TARGET` | backend.algoga.local | 스크레이프 대상(Cloud Map DNS) |
| `PROM_PORT` | 15000 | 백엔드 액추에이터 포트 |
| `PROM_PATH` | /actuator/prometheus | 메트릭 경로 |
| `SCRAPE_INTERVAL` | 5s | 스크레이프 주기 |
| `GRAFANA_UPSTREAM` | grafana:3000 | 게이트웨이 → Grafana |
| `PROMETHEUS_UPSTREAM` | prometheus:9090 | 게이트웨이 → Prometheus |
| `GF_ADMIN_PW` | (필수) | Grafana admin 비밀번호 |
| `SLACK_WEBHOOK_URL` | placeholder | 알림용 슬랙 웹훅 |
