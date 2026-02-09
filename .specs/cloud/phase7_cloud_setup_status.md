# Phase 7 Cloud Setup Status (Dev Minimal)

Last updated: 2026-02-06

## 1. 목적

Phase 7(Cloud/Platform Setup)의 개발 단계 최소 구성을 문서화한다.
보안 하드닝(NSG/서브넷 분리/Private Endpoint/Key Vault 강제)은 재구축 단계에서 적용한다.

## 2. 현재 기준 환경

- Subscription: `27db5ec6-d206-4028-b5e1-6004dca5eeef`
- Resource Group: `2dt-final-team4`
- Region: `koreacentral`
- Databricks Workspace: `2dt-final-team4-databricks-test`
- Storage Account: `2dtfinalteam4storagetest`
- ADLS Container: `2dt-final-team4-adls-test`

## 3. 완료 상태

### 3.1 Azure 스토리지/권한

- ADLS Gen2(HNS enabled) 스토리지 및 컨테이너 존재 확인
- Databricks Access Connector(`unity-catalog-access-connector`)에 다음 RBAC 부여
- `Storage Blob Data Reader`
- `Storage Blob Data Contributor`

### 3.2 Unity Catalog

- Metastore 할당 및 UC 활성화 확인
- Catalog: `2dt_final_team4_databricks_test`
- Schema: `bronze`, `silver`, `gold`
- Storage Credential: `2dt_final_team4_databricks_test` (Managed Identity 기반)
- External Location 추가:
- Name: `team4_adls_test`
- URL: `abfss://2dt-final-team4-adls-test@2dtfinalteam4storagetest.dfs.core.windows.net/`

### 3.3 Secret Scope

- Key Vault 연동 대신 Databricks-backed scope를 dev 임시 기준으로 적용
- Scope: `ledger-analytics-dev`
- Key: `salt_user_key`

### 3.4 클러스터/워크플로우 정책

- Cluster Policy 생성:
- Name: `data-pipeline-single-node-dev`
- Policy ID: `00023C6641CF09E4`
- Runtime: `13.3.x-scala2.12`
- Single-node, autotermination 범위(10~120분)
- Pipeline A Job(`57710310442212`)에 재시도/알림 반영
- `max_retries=2`
- `min_retry_interval_millis=300000`
- failure email: `2dt026@msacademy.msai.kr`

## 4. ADLS 경로 규칙(Dev)

컨테이너 루트(`abfss://2dt-final-team4-adls-test@2dtfinalteam4storagetest.dfs.core.windows.net/`) 아래에 다음 prefix를 사용한다.

- `bronze/<table_name>/date_kst=YYYY-MM-DD/`
- `silver/<table_name>/date_kst=YYYY-MM-DD/`
- `gold/<table_name>/date_kst=YYYY-MM-DD/`
- `quarantine/<table_name>/date_kst=YYYY-MM-DD/`
- `checkpoints/<pipeline_name>/`

참고: 현재 일부 테이블은 UC managed storage를 사용 중이며, 신규/이관 경로부터 `team4_adls_test` external location prefix를 사용한다.

## 5. 남은 작업(Phase 7 관점)

- 서비스 프린시플 기반 실행 주체/권한 모델 확정 및 적용
- Slack 알림 채널 연동(현재는 이메일만 설정)
- Key Vault 연동 Secret Scope 전환(재구축 단계)

## 6. 재현/점검 스크립트

- 설정 적용: `scripts/phase7/setup_minimal_cloud.sh`
- 상태 점검: `scripts/phase7/audit_cloud_state.sh`

