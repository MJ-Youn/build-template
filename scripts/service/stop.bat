@echo off
@rem ==============================================================================
@rem File: stop.bat
@rem Description: Windows 환경 Docker 컨테이너 서비스 중지 스크립트
@rem Author: 윤명준 (MJ Yun)
@rem ==============================================================================

chcp 65001 > nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_ROOT=%%~fI"

set "APP_NAME=@appName@"
if "%APP_NAME%"=="" set "APP_NAME=app"

@rem Docker Compose 명령어 확인
docker compose version >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "DOCKER_COMPOSE_CMD=docker compose"
) else (
    docker-compose version >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        set "DOCKER_COMPOSE_CMD=docker-compose"
    ) else (
        echo ❌ [오류] Docker Compose를 찾을 수 없습니다.
        exit /b 1
    )
)

set "COMPOSE_FILE=%PROJECT_ROOT%\docker\docker-compose.yml"
if not exist "%COMPOSE_FILE%" (
    set "COMPOSE_FILE=%PROJECT_ROOT%\docker-compose.yml"
)

if not exist "%COMPOSE_FILE%" (
    echo ❌ [오류] docker-compose.yml 파일을 찾을 수 없습니다: %COMPOSE_FILE%
    exit /b 1
)

echo ➡️  Docker Compose 서비스 중지 중 (%APP_NAME%)...
%DOCKER_COMPOSE_CMD% -f "%COMPOSE_FILE%" stop
if %ERRORLEVEL% equ 0 (
    echo ✅  서비스가 중지되었습니다.
) else (
    echo ❌ [오류] 서비스 중지 실패
)

endlocal
