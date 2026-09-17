@echo off
@rem ==============================================================================
@rem File: uninstall_service.bat
@rem Description: Windows 환경 Docker 컨테이너 서비스 제거 스크립트
@rem Author: 윤명준 (MJ Yun)
@rem ==============================================================================

chcp 65001 > nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PKG_ROOT=%%~fI"

set "APP_NAME=@appName@"
if "%APP_NAME%"=="" set "APP_NAME=app"

echo.
echo ================================================================
echo 🛑 Windows Docker 서비스 제거 시작 (%APP_NAME%)
echo ================================================================
echo.

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
        pause
        exit /b 1
    )
)

set "COMPOSE_FILE=%PKG_ROOT%\docker\docker-compose.yml"
if not exist "%COMPOSE_FILE%" (
    set "COMPOSE_FILE=%PKG_ROOT%\docker-compose.yml"
)

if not exist "%COMPOSE_FILE%" (
    echo ❌ [오류] docker-compose.yml 파일을 찾을 수 없습니다.
    pause
    exit /b 1
)

echo ➡️  Docker Compose 컨테이너를 중지하고 제거합니다...
%DOCKER_COMPOSE_CMD% -f "%COMPOSE_FILE%" down
if %ERRORLEVEL% neq 0 (
    echo ⚠️  Docker Compose down 실행 중 경고 또는 에러가 발생했습니다.
) else (
    echo ✅  Docker Compose 컨테이너가 성공적으로 제거되었습니다.
)

echo.
pause
endlocal
