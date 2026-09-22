@echo off
@rem ==============================================================================
@rem File: start.bat
@rem Description: Windows 환경 Docker 컨테이너 서비스 시작 스크립트
@rem Author: 윤명준 (MJ Yun)
@rem ==============================================================================

chcp 65001 > nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_ROOT=%%~fI"

set "APP_NAME=@appName@"
set "IMAGE_TAG=@dockerImage@"
set "HTTP_PORT=@httpPort@"

if "%APP_NAME%"=="" set "APP_NAME=app"
if "%IMAGE_TAG%"=="" set "IMAGE_TAG=%APP_NAME%:latest"
if "%HTTP_PORT%"=="" set "HTTP_PORT=8443"

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

echo ➡️  Docker Compose 서비스 시작 중 (%APP_NAME%)...
set "DOCKER_IMAGE=%IMAGE_TAG%"
set "CONTAINER_NAME=%APP_NAME%"
set "HTTP_PORT=%HTTP_PORT%"
set "DEST_DIR=%PROJECT_ROOT%"
set "LOG_PATH=%PROJECT_ROOT%\log"

%DOCKER_COMPOSE_CMD% -f "%COMPOSE_FILE%" up -d
if %ERRORLEVEL% equ 0 (
    echo ✅  서비스가 성공적으로 시작되었습니다.
    echo 🔹 서비스 주소: http://localhost:%HTTP_PORT%
) else (
    echo ❌ [오류] 서비스 시작 실패
)

endlocal
