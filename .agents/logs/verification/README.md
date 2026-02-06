# Verification Logs Guide

## Naming

- L0: `YYYYMMDD_phaseX_L0.txt`
- L1: `YYYYMMDD_phaseX_L1.txt`
- L2: `YYYYMMDD_phaseX_L2.txt`
- L3/E2E: `YYYYMMDD_phaseX_L3.txt` 또는 `e2e_smoke_YYYYMMDDTHHMMSSZ.txt`

## Minimum Content

1. 실행 날짜(UTC)
2. 실행 명령
3. 통과/실패 여부
4. 실패 시 요약 원인 및 재시도 여부

템플릿은 `templates/` 디렉터리를 사용한다.
