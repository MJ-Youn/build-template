@echo off
@rem ==============================================================================
@rem File: install_service.bat
@rem Description: Windows 환경 서비스 설치 및 Docker 컨테이너 배포 스크립트 (방안 C)
@rem Author: 윤명준 (MJ Yun)
@rem ==============================================================================

chcp 65001 > nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
@rem deploy 폴더 내에서 실행되었는지 확인하여 PKG_ROOT 계산
for %%I in ("%SCRIPT_DIR%..") do set "PKG_ROOT=%%~fI"

set "APP_NAME=@appName@"
set "IMAGE_TAG=@dockerImage@"
set "HTTP_PORT=@httpPort@"

if "%APP_NAME%"=="" set "APP_NAME=app"
if "%IMAGE_TAG%"=="" set "IMAGE_TAG=%APP_NAME%:latest"
if "%HTTP_PORT%"=="" set "HTTP_PORT=8443"

echo.
echo ================================================================
echo 🚀 Windows 환경 감지됨 - Docker 컨테이너 배포 모드(방안 C)
echo ================================================================
echo ℹ️  Windows 환경에서는 Docker Compose 배포(방안 C)만 지원합니다.
echo    - 애플리케이션: %APP_NAME%
echo    - 이미지 태그  : %IMAGE_TAG%
echo    - 서비스 포트  : %HTTP_PORT%
echo ================================================================
echo.

@rem 1. Docker 설치 여부 확인
where docker >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ [오류] Docker 실행 파일을 찾을 수 없습니다.
    echo    Docker Desktop이 설치되어 있고 시스템 PATH 환경변수에 등록되어 있는지 확인해주세요.
    echo.
    pause
    exit /b 1
)

@rem 2. Docker 데몬 실행 여부 확인
echo ➡️  Docker 데몬 상태 확인 중...
docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ [오류] Docker 데몬이 실행 중이지 않습니다.
    echo    Docker Desktop을 실행한 후 다시 시도해주세요.
    echo.
    pause
    exit /b 1
)
echo ✅  Docker 데몬 정상 동작 확인

@rem 3. Docker Compose 명령어 확인 (docker compose vs docker-compose)
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
echo ℹ️  Docker Compose 명령어: %DOCKER_COMPOSE_CMD%

@rem 4. Docker 이미지 준비 (Load 또는 Build)
set "TAR_FILE=%PKG_ROOT%\%APP_NAME%.tar"
set "DOCKERFILE_PATH=%PKG_ROOT%\docker\Dockerfile"

if exist "%TAR_FILE%" (
    echo ➡️  Docker 이미지 로드 중 (%TAR_FILE%)...
    docker load -i "%TAR_FILE%"
    if !ERRORLEVEL! neq 0 (
        echo ❌ [오류] Docker 이미지 로드에 실패했습니다.
        pause
        exit /b 1
    )
    echo ✅  Docker 이미지 로드 완료
) else if exist "%DOCKERFILE_PATH%" if exist "%PKG_ROOT%\\libs" (
    echo ➡️  Docker 이미지 빌드 중 (Dockerfile 기반)...
    echo    - 빌드 컨텍스트: %PKG_ROOT%
    echo    - Dockerfile    : %DOCKERFILE_PATH%
    echo    - 이미지 태그  : %IMAGE_TAG%
    docker build --build-arg APP_NAME="%APP_NAME%" -t "%IMAGE_TAG%" -f "%DOCKERFILE_PATH%" "%PKG_ROOT%"
    if !ERRORLEVEL! neq 0 (
        echo ❌ [오류] Docker 이미지 빌드에 실패했습니다.
        pause
        exit /b 1
    )
    echo ✅  Docker 이미지 빌드 완료: %IMAGE_TAG%
) else (
    echo ➡️  원격 레지스트리에서 Docker 이미지 다운로드 중 (docker pull %IMAGE_TAG%)...
    docker pull "%IMAGE_TAG%"
    if !ERRORLEVEL! neq 0 (
        echo ❌ [오류] Docker 이미지 다운로드에 실패했습니다: %IMAGE_TAG%
        echo    사설 레지스트리인 경우 'docker login' 및 Docker 데몬 설정을 확인해주세요.
        pause
        exit /b 1
    )
    echo ✅  Docker 이미지 다운로드 완료: %IMAGE_TAG%
)

@rem 5. docker-compose.yml 탐색
set "COMPOSE_FILE=%PKG_ROOT%\docker\docker-compose.yml"
if not exist "%COMPOSE_FILE%" (
    set "COMPOSE_FILE=%PKG_ROOT%\docker-compose.yml"
)

if not exist "%COMPOSE_FILE%" (
    echo ❌ [오류] docker-compose.yml 파일을 찾을 수 없습니다: %COMPOSE_FILE%
    pause
    exit /b 1
)

@rem 6. 환경 변수 설정 및 Docker Compose 실행
echo ➡️  Docker Compose 서비스 시작 중...
set "DOCKER_IMAGE=%IMAGE_TAG%"
set "CONTAINER_NAME=%APP_NAME%"
set "HTTP_PORT=%HTTP_PORT%"
set "DEST_DIR=%PKG_ROOT%"
set "LOG_PATH=%PKG_ROOT%\log"

if not exist "%PKG_ROOT%\log" mkdir "%PKG_ROOT%\log"

%DOCKER_COMPOSE_CMD% -f "%COMPOSE_FILE%" up -d
if %ERRORLEVEL% neq 0 (
    echo ❌ [오류] Docker Compose 컨테이너 시작에 실패했습니다.
    pause
    exit /b 1
)

echo.
echo ================================================================
echo ✅ Windows Docker 서비스 배포 및 시작이 완료되었습니다!
echo ================================================================
echo 🔹 서비스 접속 주소 : http://localhost:%HTTP_PORT%
echo 🔹 로그 디렉토리    : %PKG_ROOT%\log
echo 🔹 상태 확인 스크립트: bin\status.bat
echo 🔹 서비스 중지 스크립트: bin\stop.bat
echo 🔹 서비스 재시작 스크립트: bin\start.bat
echo ================================================================
echo.

pause
endlocal
