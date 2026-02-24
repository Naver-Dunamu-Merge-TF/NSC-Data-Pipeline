# G2-0 Gate Unlock Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task.

**Goal:** G2 착수 선행조건을 `SEC-008` 조건부 승인 상태 기준으로 잠그고, G2-0 착수 승인 증적을 고정한다.

**Architecture:** 로드맵 문서에 G2 실행 번들 현황 섹션을 추가해 `G2-0` 상태를 명시하고, 별도 verification memo에 조건부 승인 근거/리스크/철회 조건을 문서화한다. 구현 후 spec-compliance 리뷰와 code-quality 리뷰를 순차 수행한다.

**Tech Stack:** Markdown docs, shell verification (`rg`, `test -f`)

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

1. 구현 서브에이전트가 Task 1 범위만 변경한다.
2. 스펙 리뷰 서브에이전트가 요구사항 충족/초과 구현 여부를 점검한다.
3. 코드 품질 리뷰 서브에이전트가 유지보수성과 리스크를 점검한다.
4. 이슈가 발견되면 구현 서브에이전트가 수정 후 동일 리뷰를 재실행한다.

### Task 1: Lock G2-0 Gate Unlock Evidence

**Files:**
- Modify: `.roadmap/implementation_roadmap.md`
- Create: `.agents/logs/verification/20260224_g2_0_gate_unlock.md`

**Task requirements:**
1. `.roadmap/implementation_roadmap.md`에 G2 실행 번들 상태 섹션을 추가하고 `G2-0`를 명시한다.
2. `G2-0` 상태는 `Done`으로 기록하고, 근거는 `SEC-008`의 조건부 `InProgress` 및 D-049 조건부 승인 메모를 참조한다.
3. `.agents/logs/verification/20260224_g2_0_gate_unlock.md`에 아래 항목을 기록한다.
   - 입력 증적(`SEC-008` 로드맵 행, D-049, `20260224_sec007_sec008_conditional_approval.md`)
   - G2 착수 허용 범위(모니터링 v1 작업 착수 허용)
   - 잔여 리스크(`SEC-003` L3, SEC-007 cadence 6샘플)
   - 철회 조건(staged smoke 재실패 또는 external location 이슈 재발)
4. 기존 SEC/MON/GOV task status는 G2-0 범위 밖에서 변경하지 않는다.
5. 변경 후 아래 검증 명령을 실행하고 결과를 메모에 반영한다.
   - `rg -n "G2-0|SEC-008|D-049" .roadmap/implementation_roadmap.md .agents/logs/verification/20260224_g2_0_gate_unlock.md`
   - `test -f .agents/logs/verification/20260224_sec007_sec008_conditional_approval.md`

**Verification level:** Documentation-only exception (L0-L2 skipped), but command evidence is mandatory.
