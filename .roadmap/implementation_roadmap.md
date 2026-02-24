# 실행 로드맵 (Workstream 기반, 운영완결형, 증적기반 DoD)

Last updated: 2026-02-24

## 1) 목적과 범위

이 로드맵은 기존 Phase 체크리스트를 Workstream 중심으로 재편한 실행 기준이다.
문서 SSOT 기준의 미구현/미완료 항목을 추적하며, 완료 표시는 검증 증적이 있을 때만 허용한다.

운영 전제(2026-02-23 재검증):
- 인프라 리소스는 인프라 담당이 사전 프로비저닝한 자산을 사용한다.
- 데이터 파이프라인 팀은 신규 리소스 생성 대신 검증/바인딩/전환 실행에 집중한다.
- 2026-02-23 인프라 handoff 재검증 증적은 `.agents/logs/verification/20260223_infra_handoff_validation.md`를 기준으로 한다.

포함 범위:
- Secure Rebuild: cloud rebuild 12/12.1 미완료 항목
- Monitoring: Azure Monitoring M1~M4 실행 항목
- Cutover/Hypercare: preflight/exit + dry-run + production cutover
- Governance/Evidence: 문서 정합화 + 증적 운영

## 2) 상태/필드 규약

### 2.1 상태(enum)

- `NotStarted`: 착수 전, 검증 증적 없음
- `InProgress`: 실행 중, 부분 증적 존재
- `Blocked`: 외부 선행조건 미충족으로 진행 중단
- `Done`: DoD 충족 + 증적 확보

### 2.2 Task 표현 타입(필수)

모든 task는 다음 필드를 포함한다.
- `task_id`
- `status`
- `priority`
- `depends_on`
- `source_doc`
- `dod`
- `verification_level`
- `evidence_path`
- `owner`
- `target_gate`

### 2.3 게이트 정의

- `G1`: Secure Binding Ready (사전 프로비저닝 자산 검증 + 권한/시크릿 바인딩 완료)
- `G2`: Monitoring v1 Live (Core 4 알림 + Workbook + runbook 링크 완료)
- `G3`: Cutover Rehearsal Passed (dry-run/backfill/incremental/rollback 리허설 통과)
- `G4`: Prod Cutover + Hypercare Complete

### 2.4 G2 execution bundle status

| bundle_id | status | evidence | note |
|---|---|---|---|
| G2-0 | Done | WS-SEC `SEC-008` is conditional `InProgress`; D-049 conditional approval memo: `.agents/logs/verification/20260224_sec007_sec008_conditional_approval.md`; G2-0 unlock memo: `.agents/logs/verification/20260224_g2_0_gate_unlock.md` | Unlock scope is limited to starting Monitoring v1 work. |
| G2-1 | Done | `.agents/logs/verification/20260224_mon001_signal_wiring.md`; `.agents/logs/verification/20260224_mon002_resource_mapping.md`; `.agents/logs/verification/20260224_gov001_current_planned_matrix.md`; `.agents/logs/verification/20260224_gov002_ops_evidence_baseline.md`; signoff: `.agents/logs/verification/20260224_g2_1_signal_baseline_signoff.md` | Signal wiring + monitoring baseline + governance evidence baseline synchronized. |

G2-0 precedence rule:
- `G2-0 Done` allows only WS-MON start activities while `SEC-008` is conditional `InProgress` under D-049.
- This rule does not imply `SEC-008 Done` and does not imply final G1 signoff.
- WS-MON `depends_on=SEC-008` remains effective for closure; G2-0 only unlocks start execution.

## 3) Workstream Backlog

### 3.1 WS-SEC (Security And Pre-Provisioned Resource Binding)

#### 완료 항목 (Done)

완료 항목 없음.

#### 미완료 항목 (세부 태스크)

| task_id | status | priority | depends_on | source_doc | dod | verification_level | evidence_path | owner | target_gate | 세부 태스크 |
|---|---|---|---|---|---|---|---|---|---|---|
| SEC-001 | Done | P0 | - | `.specs/cloud/cloud_migration_rebuild_plan.md` | 인프라팀 handoff 자산 목록(workspace, storage, UC, external location, KV, SP)을 확정하고 운영 잠금 버전을 기록 | L3 | `.agents/logs/verification/20260223_sec001_subagent_review.md` | Platform + DataEng | G1 | 1) handoff 인벤토리 템플릿 확정<br>2) 자산 식별값/권한 주체 수집 및 증적 로그 적재(`20260223_infra_cli_audit.log`)<br>3) 운영 잠금 버전/변경이력 기록(완료) |
| SEC-003 | InProgress | P0 | SEC-001 | `.specs/ops/cutover_preflight_exit_template.md`, `scripts/phase7/sec003_sec004_binding_window.sh` | UC 권한(`USE CATALOG/SCHEMA`, `SELECT`, `MODIFY`) 및 external location 접근 검증 통과(서버리스 SEC window 기준) | L3 | `.agents/logs/verification/YYYYMMDD_sec003_uc_external_location_serverless.md` | DataEng + Infra | G1 | 1) UC grant 매트릭스 확정(그룹 + 검증자 임시 권한)<br>2) `sec003_sec004_binding_window.sh`로 ACL 적용<br>3) `verify_sec003_sec004_l3.sh`로 external location read/write 검증 |
| SEC-004 | Done | P0 | SEC-001 | `.specs/cloud/cloud_migration_rebuild_plan.md`, `.specs/decision_open_items.md`, `scripts/phase7/sec003_sec004_binding_window.sh` | `ledger-analytics-dev` scope backend를 `AZURE_KEYVAULT`로 정렬 완료(이번 사이클은 backend 정렬 기준으로 종료) | L1 | `.agents/logs/verification/20260224_sec004_scope_backend_alignment_only.md` | Infra | G1 | 1) 기존 `ledger-analytics-dev` backend가 `DATABRICKS`임을 확인<br>2) Key Vault(`nsc-kv-dev`) 기반 scope 재생성 완료<br>3) 최종 backend=`AZURE_KEYVAULT` 재검증 |
| SEC-005 | Done | P0 | SEC-004 | `.specs/decision_open_items.md` (D-018, D-044, D-045, D-046, D-048), `.specs/cloud/cloud_migration_rebuild_plan.md` | 서비스 프린시플 `run_as` 전환 + UC ACL 최소권한 적용 + staged smoke(L3) 수렴 성공(2026-02-24 retry3) | L3 | `.agents/logs/verification/20260224_d046_smoke_recovery_summary_d046_smoke_srvless_retry3_20260224T033753Z.json` | Infra + DataEng | G1 | 1) A/Silver/B/C 서버리스 wiring 배포 및 runtime assertion PASS<br>2) SP+verifier ACL assertions PASS (`20260223_sec005_acl_assertions.json`, `20260223_sec005_verifier_acl_assertions.json`)<br>3) D-046 staged smoke 표준(`sync_dim_rule_scd2 -> A/Silver -> B/C`) 실행에서 stage A/Silver/B/C 모두 PASS (`20260224_d046_smoke_recovery_summary_d046_smoke_srvless_retry3_20260224T033753Z.json`)<br>4) SEC-003 external location 검증은 독립 게이트로 분리 유지(SEC-005 종료 선행조건에서 제외) |
| SEC-006 | Done | P1 | SEC-001, SEC-004 | `.specs/cloud/cloud_migration_rebuild_plan.md#12.1`, `configs/dev.yaml`, `configs/common.yaml` | `configs/dev.yaml`/`configs/common.yaml`의 host/id/catalog/external_location/base_path/secret 값이 실측값과 일치 | L1 | `.agents/logs/verification/20260223_sec006_config_alignment.md` | DataEng | G1 | 1) deterministic baseline 파일(`20260223_sec006_expected_values.env`) 고정<br>2) pre/post check 모두 mismatch 0 확인<br>3) L1 unit gate(`194 passed`) 증적 반영 완료 |
| SEC-007 | InProgress | P1 | SEC-003, SEC-006 | `.specs/cloud/cloud_migration_rebuild_plan.md#12.1`, `docs/plans/2026-02-24-d045-smoke-convergence-recovery.md`, `.specs/decision_open_items.md` (D-049) | 조건부 승인: staged smoke 1회 PASS(2026-02-24 retry3)를 G1 임시 통과 근거로 수용, `SEC-003` L3 + cadence 성공 샘플 6건은 후속 종료 조건으로 이관 | L3 | `.agents/logs/verification/20260224_sec007_sec008_conditional_approval.md` | DataEng | G1 | 1) D-049 기준으로 SEC-007을 Blocked에서 조건부 진행 상태로 전환<br>2) 잔여 필수항목(`SEC-003` external location L3, cadence `sample_count>=6`)을 후속 트랙으로 고정<br>3) 조건부 기간에는 staged smoke 실패 재발 시 즉시 조건부 승인 철회 |
| SEC-008 | InProgress | P0 | SEC-003, SEC-004, SEC-005, SEC-007 | `.specs/cloud/cloud_migration_rebuild_plan.md`, `.specs/ops/cutover_preflight_exit_template.md`, `.specs/decision_open_items.md` (D-049) | 조건부 승인: G1 체크리스트를 임시 승인으로 통과시키되 최종 서명은 `SEC-003` L3 및 SEC-007 cadence 종료 후 확정 | L3 | `.agents/logs/verification/20260224_sec007_sec008_conditional_approval.md` | Platform | G1 | 1) Infra/Platform/DataEng 조건부 합동 서명 기록<br>2) 잔여 오픈 항목(`SEC-003`, SEC-007 cadence)과 리스크 수용 범위 명시<br>3) 잔여 항목 완료 시 SEC-008 최종 서명 로그로 대체 |

#### 2026-02-23 인프라 재검증 스냅샷

| 구분 | 상태 | 근거 |
|---|---|---|
| Azure 리소스 프로비저닝/조회 | PASS | `.agents/logs/verification/20260223_infra_cli_audit.log` |
| SQL AAD-only 및 Private Access | PASS | `az sql server ad-only-auth get`, `az network private-endpoint-connection list` |
| ACR/KV/ADLS/Bastion private posture | PASS | `publicNetworkAccess=Disabled` + private endpoint 승인 |
| Postgres/Event Hubs private-only posture | FAIL | `publicNetworkAccess=Enabled` 확인 |
| Databricks Workspace 인증/접근 | PASS | `databricks auth describe`, `databricks current-user me` |
| Databricks bootstrap 정합(catalog/scope/policy) | FAIL | catalog 불일치, scope 0건, 정책 미존재 |

### 3.2 WS-MON (Azure Monitoring v1 Rollout)

#### 완료 항목 (Done)

| task_id | status | priority | depends_on | source_doc | dod | verification_level | evidence_path | owner | target_gate |
|---|---|---|---|---|---|---|---|---|---|
| MON-001 | Done | P0 | SEC-008 | `.specs/ops/azure_monitoring_integration_plan.md` (M1) | Databricks diagnostic logs -> Log Analytics 연결 + A/B/C 최소 리소스 매핑 스냅샷(Workspace, LAW resource ID/GUID, job name) + 로그 유입 확인 완료 | L3 | `.agents/logs/verification/20260224_mon001_signal_wiring.md` | Platform | G2 |
| MON-002 | Done | P1 | MON-001 | `.specs/ops/azure_monitoring_integration_plan.md` (M1) | MON-001 최소 매핑을 dev/prod 확장 매핑표로 정리하고 공통 명명 규칙을 SSOT 문서에 고정 | L1 | `.agents/logs/verification/20260224_mon002_resource_mapping.md` | Platform | G2 |

#### 미완료 항목 (세부 태스크)

| task_id | status | priority | depends_on | source_doc | dod | verification_level | evidence_path | owner | target_gate | 세부 태스크 |
|---|---|---|---|---|---|---|---|---|---|---|
| MON-003 | NotStarted | P0 | MON-001 | `.specs/ops/azure_monitoring_integration_plan.md` (M2) | Core Execution Alerts 4종(Job failure, success delay, retry exhausted, cluster start/timeout) 생성 완료 | L3 | `.agents/logs/verification/20260212_mon_core4_alerts.log` | Platform | G2 | 1) 알림 규칙 4종 생성<br>2) 쿼리/임계치 검증<br>3) 활성 상태 확인 |
| MON-004 | NotStarted | P0 | MON-003 | `.specs/ops/azure_monitoring_integration_plan.md`, `.specs/ops/operations_runbook.md` | Severity + Owner Action Group 라우팅 연결 완료 | L3 | `.agents/logs/verification/20260212_mon_action_group_binding.log` | Platform + Ops | G2 | 1) Action Group 분리 구성<br>2) 규칙별 라우팅 연결<br>3) 수신자/채널 검증 |
| MON-005 | NotStarted | P0 | MON-004 | `.specs/ops/azure_monitoring_integration_plan.md` (M2) | 테스트 알람 최소 1회 발화 및 수신 확인 | L3 | `.agents/logs/verification/20260212_mon_test_alert_fire.log` | Ops | G2 | 1) 테스트 경보 발화 시나리오 실행<br>2) 수신 여부/지연 시간 확인<br>3) 증적 및 이슈 기록 |
| MON-006 | NotStarted | P1 | MON-003 | `.specs/ops/azure_monitoring_integration_plan.md` (M3) | Workbook v1 생성 + 운영팀 공유 권한 부여 | L3 | `.agents/logs/verification/20260212_mon_workbook_publish.log` | Ops | G2 | 1) Workbook v1 템플릿 구성<br>2) KPI/타임라인/인프라 섹션 연결<br>3) 운영팀 공유 권한 설정 |
| MON-007 | NotStarted | P1 | MON-006 | `.specs/ops/operations_runbook.md`, `.specs/ops/azure_monitoring_integration_plan.md` | Runbook에 dashboard 링크/alert rule ID 반영 완료 | L1 | `.agents/logs/verification/20260212_mon_runbook_link_sync.md` | DataEng + Ops | G2 | 1) runbook 링크/ID 반영<br>2) triage 절차 경보 ID 기준 정렬<br>3) 상호 리뷰 후 확정 |
| MON-008 | NotStarted | P1 | MON-007 | `.specs/ops/azure_monitoring_integration_plan.md` (M4) | 월 1회 game-day 운영 캘린더 등록 + 1회차 실행 증적 확보 | L3 | `.agents/logs/verification/20260212_mon_gameday_round1.log` | Ops | G2 | 1) 월간 game-day 일정 등록<br>2) 실패/지연 시나리오 1회 수행<br>3) 개선 액션아이템 도출 |
| MON-009 | InProgress | P2 | MON-007 | `.specs/ops/azure_monitoring_integration_plan.md#8`, `.specs/project_specs.md#12` | v2 테이블 기반 알림은 backlog gate로 분리되어 v1 범위와 충돌 없음을 문서로 고정 | L1 | `.agents/logs/verification/20260212_mon_v1_v2_boundary.md` | DataEng | G2 | 1) v1/v2 경계 매트릭스 작성<br>2) v2 항목 backlog gate 태깅<br>3) 관련 문서 교차 정렬 |

### 3.3 WS-CUT (Cutover, Rehearsal, Hypercare)

#### 완료 항목 (Done)

완료 항목 없음.

#### 미완료 항목 (세부 태스크)

| task_id | status | priority | depends_on | source_doc | dod | verification_level | evidence_path | owner | target_gate | 세부 태스크 |
|---|---|---|---|---|---|---|---|---|---|---|
| CUT-001 | NotStarted | P0 | SEC-008 | `.specs/ops/cutover_preflight_exit_template.md` | `T_cutover_utc`, operator, source/target env, change window 메타 확정 | L1 | `.agents/logs/verification/20260212_cut_metadata_lock.md` | Ops | G3 | 1) `T_cutover_utc` 및 윈도우 확정<br>2) operator/source/target 입력<br>3) 메타데이터 잠금 |
| CUT-002 | NotStarted | P0 | CUT-001 | `.specs/ops/cutover_preflight_exit_template.md#2` | Preflight checklist 전 항목 완료(권한/시크릿/파라미터/workflow 순서/rule table/monitoring 범위) | L3 | `.agents/logs/verification/20260212_cut_preflight_complete.md` | Ops + DataEng | G3 | 1) Preflight 체크 항목별 검증<br>2) 증적 링크 부착<br>3) 사전 승인 서명 |
| CUT-003 | InProgress | P1 | CUT-002 | `.specs/ops/cutover_preflight_exit_template.md#2`, `databricks.yml` | `bootstrap_catalog`, `sync_dim_rule_scd2`, `pipeline_silver_materialization` 배포/실행 경로 확인 | L2 | `.agents/logs/verification/20260212_cut_jobs_path_check.log` | DataEng | G3 | 1) 3개 job 배포 경로 점검<br>2) 파라미터/권한 검증<br>3) 실행 결과 캡처 |
| CUT-004 | InProgress | P1 | CUT-002 | `.specs/ops/cutover_preflight_exit_template.md`, `.specs/ops/operations_runbook.md` | Pipeline B 동일 `run_id` 재실행 검증 계획 수립 및 SQL 체크 쿼리 준비 | L2 | `.agents/logs/verification/20260212_cut_pipeline_b_rerun_plan.md` | DataEng | G3 | 1) 동일 `run_id` rerun 시나리오 정의<br>2) 중복 검증 SQL 템플릿 확정<br>3) 실패 시 대응 플로우 문서화 |
| CUT-005 | NotStarted | P0 | CUT-003 | `.specs/ops/cutover_preflight_exit_template.md#3` | Pipeline A -> Silver -> B/C backfill dry-run 완료 | L3 | `.agents/logs/verification/20260212_cut_dryrun_backfill.log` | DataEng | G3 | 1) A/Silver/B/C 순차 백필 실행<br>2) row count/CRITICAL 추이 검증<br>3) 재실행 수렴 확인 |
| CUT-006 | NotStarted | P0 | CUT-005 | `.specs/cloud/cloud_migration_rebuild_plan.md#6` | `T_cutover_utc` 이후 incremental 전환 리허설 완료 | L3 | `.agents/logs/verification/20260212_cut_incremental_switch.log` | DataEng + Ops | G3 | 1) cutover 시점 이후 증분 실행<br>2) 누락/중복 여부 확인<br>3) pipeline_state 최신성 검증 |
| CUT-007 | NotStarted | P0 | CUT-006 | `.specs/cloud/cloud_migration_rebuild_plan.md#10` | 롤백 리허설(Workflow 전환 + 재백필) 성공 | L3 | `.agents/logs/verification/20260212_cut_rollback_rehearsal.log` | Ops + DataEng | G3 | 1) 롤백 트리거 시나리오 실행<br>2) workflow 전환 및 재백필 수행<br>3) 복구 시간/SLA 확인 |
| CUT-008 | NotStarted | P0 | CUT-005, CUT-006, CUT-007 | `.specs/ops/cutover_preflight_exit_template.md#4`, `.specs/cloud/cloud_migration_rebuild_plan.md#9` | Exit Criteria 표의 모든 stage pass + SQL 증적 링크 완료 | L3 | `.agents/logs/verification/20260212_cut_exit_criteria_evidence.md` | Ops | G3 | 1) Exit Criteria stage별 상태 입력<br>2) SQL 증적 링크 연결<br>3) G3 승인 회의 기록 |
| CUT-009 | NotStarted | P0 | CUT-008, MON-008 | `.specs/ops/cutover_preflight_exit_template.md#3` | 프로덕션 컷오버 실행 및 기존/신규 workflow 전환 완료 | L3 | `.agents/logs/verification/20260212_cut_prod_cutover.log` | Ops + Platform | G4 | 1) 기존 workflow 중지/신규 활성화<br>2) 첫 운영 실행 모니터링<br>3) 전환 완료 공지 |
| CUT-010 | NotStarted | P1 | CUT-009 | `.specs/ops/cutover_preflight_exit_template.md#5`, `.specs/cloud/cloud_migration_rebuild_plan.md` | Hypercare 관측 창 통과 + 운영 인수인계/체크리스트 확정 | L3 | `.agents/logs/verification/20260212_cut_hypercare_handover.md` | Ops + DataEng | G4 | 1) Hypercare 기간 지표 관측<br>2) 잔여 이슈 종료/전달<br>3) 운영 인수인계 문서 확정 |

### 3.4 WS-GOV (Governance And Evidence)

#### 완료 항목 (Done)

| task_id | status | priority | depends_on | source_doc | dod | verification_level | evidence_path | owner | target_gate |
|---|---|---|---|---|---|---|---|---|---|
| GOV-005 | Done | P0 | - | `.roadmap/implementation_roadmap.md` | Legacy Phase ↔ Workstream 매핑 표를 문서에 반영 | L1 | `.roadmap/implementation_roadmap.md` | DataEng | G1 |
| GOV-001 | Done | P0 | - | `.specs/project_specs.md#12`, `.specs/data_contract.md` | Current/Planned 동기화 점검 매트릭스 작성 및 월 1회 갱신 규칙 고정 | L1 | `.agents/logs/verification/20260224_gov001_current_planned_matrix.md` | DataEng | G2 |
| GOV-002 | Done | P1 | - | `.specs/project_specs.md#12`, `.specs/ops/operations_runbook.md` | `bootstrap_catalog`, `bad_records_retention_cleanup` 정기 증적 누적 기준선 확정 | L1 | `.agents/logs/verification/20260224_gov002_ops_evidence_baseline.md` | Ops + DataEng | G2 |

#### 미완료 항목 (세부 태스크)

| task_id | status | priority | depends_on | source_doc | dod | verification_level | evidence_path | owner | target_gate | 세부 태스크 |
|---|---|---|---|---|---|---|---|---|---|---|
| GOV-003 | NotStarted | P1 | GOV-002 | `.specs/ops/operations_runbook.md` | 룰 변경 거버넌스(승인/버전/유효기간) 정기 점검 증적 1회 확보 | L2 | `.agents/logs/verification/20260212_gov_rule_governance_review.log` | Ops | G2 | 1) 룰 변경 이력/승인 흐름 점검<br>2) 유효기간/중복 rule 검증<br>3) 개선 이슈 기록 |
| GOV-004 | NotStarted | P2 | - | `.roadmap/implementation_roadmap.md` | 주간 로드맵 상태 리뷰(상태/블로커/증적) 운영 루틴 고정 | L1 | `.agents/logs/verification/20260212_gov_roadmap_weekly_review.md` | DataEng Lead | G2 | 1) 주간 리뷰 일정 고정<br>2) 상태/블로커 보고 템플릿 확정<br>3) 주간 기록 아카이브 경로 지정 |
| GOV-006 | Done | P1 | - | `.specs/project_specs.md`, `.specs/cloud/cloud_migration_rebuild_plan.md` | 핵심 참조 문서의 로드맵 링크를 Workstream 기준으로 정렬 | L1 | `.agents/logs/verification/20260223_gov_reference_alignment.md` | DataEng | G1 | 1) 참조 링크 최신화<br>2) 링크 무결성 검증<br>3) 정렬 증적 업데이트 |
| GOV-007 | InProgress | P2 | MON-009 | `.specs/ops/azure_monitoring_integration_plan.md`, `.specs/project_specs.md#12` | 모니터링 v2 확장 항목을 backlog gate로 분리 유지 | L1 | `.agents/logs/verification/20260212_gov_monitoring_v2_backlog.md` | Ops + DataEng | G2 | 1) v2 확장 항목 태깅 유지<br>2) G2 완료 기준에서 분리 확인<br>3) 관련 문서 일관성 점검 |

## 4) 검증 시나리오 (로드맵 품질 게이트)

| check_id | 검증 항목 | pass 기준 |
|---|---|---|
| ROADMAP-QA-01 | 누락 검증 | 소스 문서 미완료 항목이 task로 1:1 매핑됨 |
| ROADMAP-QA-02 | 중복 검증 | 동일 작업이 복수 WS에 중복 등록되지 않음 |
| ROADMAP-QA-03 | 참조 검증 | 모든 `source_doc`가 유효 경로를 가짐 |
| ROADMAP-QA-04 | DoD 완결성 | 모든 task의 `dod`/`verification_level`/`evidence_path`가 비어있지 않음 |
| ROADMAP-QA-05 | 호환 검증 | Legacy Phase 참조 문장이 매핑표로 해석 가능 |

## 5) 기본 가정과 디폴트

1. 외부 Azure 리소스 작업은 로드맵 관리 범위에 포함한다.
2. 완료 상태(`Done`)는 증적 링크 없이는 허용하지 않는다.
3. Workstream 전환 후에도 역사적 맥락 보존을 위해 Legacy 매핑을 유지한다.
4. 모니터링은 v1 Core 4를 우선 완료하고, v2 테이블 기반 알림은 후속 gate로 분리한다.

## 6) Legacy Phase ↔ Workstream 매핑

| Legacy Phase | Workstream 매핑 | 비고 |
|---|---|---|
| Phase 11 Secure Environment Rebuild | WS-SEC, WS-MON(M1~M2), WS-GOV(GOV-006) | 인프라 생성 자체는 인프라팀 소관, 데이터팀은 바인딩/검증 담당 |
| Phase 12 Migration Rehearsal | WS-CUT(CUT-001~CUT-008), WS-SEC(SEC-007~SEC-008) | dry-run/backfill/incremental/rollback 리허설 |
| Phase 13 Production Cutover + Hypercare | WS-CUT(CUT-009~CUT-010), WS-MON(M4), WS-GOV | 컷오버 실행, 관측, 인수인계 |

## 7) 참조

- `.specs/project_specs.md`
- `.specs/data_contract.md`
- `.specs/cloud/cloud_migration_rebuild_plan.md`
- `.specs/ops/azure_monitoring_integration_plan.md`
- `.specs/ops/cutover_preflight_exit_template.md`
- `.specs/ops/operations_runbook.md`
- `.specs/decision_open_items.md`
- `.agents/logs/verification/20260223_infra_handoff_validation.md`
