@echo off
set APP_URL=http://localhost:3000

REM Start your application container in background first (or connect to staging)

REM Run OWASP ZAP baseline scan
docker run --rm --network="host" -v "%cd%":/zap/wrk/:rw owasp/zap2docker-stable zap-baseline.py -t %APP_URL% -r security-reports\zap-report.html -J security-reports\zap-results.json

pause
