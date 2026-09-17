@echo off
@rem ==============================================================================
@rem File: build_deploy.bat
@rem Description: Windows 환경 원스탑 빌드 및 배포 자동화 스크립트 (build_deploy.bat)
@rem Author: 윤명준 (MJ Yun)
@rem ==============================================================================

chcp 65001 > nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "ENV_VALUE="
set "EXTRA_ARGS="
set "SKIP_PULL=false"

@rem 인자 파싱
:parse_args
if "%~1"=="" goto end_parse

if /i "%~1"=="--no-pull" (
    set "SKIP_PULL=true"
    shift
    goto parse_args
)

if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
if /i "%~1"=="help" goto show_help

@rem -Penv= 또는 -Denv=
set "ARG=%~1"
if "!ARG:~0,6!"=="-Penv=" (
    set "ENV_VALUE=!ARG:~6!"
    shift
    goto parse_args
)
if "!ARG:~0,6!"=="-Denv=" (
    set "ENV_VALUE=!ARG:~6!"
    shift
    goto parse_args
)
if "!ARG:~0,6!"=="--env=" (
    set "ENV_VALUE=!ARG:~6!"
    shift
    goto parse_args
)

@rem 환경 단독 인자 (dev, prod, local, test, stage, qa)
if /i "%~1"=="dev" set "ENV_VALUE=dev" & shift & goto parse_args
if /i "%~1"=="prod" set "ENV_VALUE=prod" & shift & goto parse_args
if /i "%~1"=="local" set "ENV_VALUE=local" & shift & goto parse_args
if /i "%~1"=="test" set "ENV_VALUE=test" & shift & goto parse_args
if /i "%~1"=="stage" set "ENV_VALUE=stage" & shift & goto parse_args
if /i "%~1"=="qa" set "ENV_VALUE=qa" & shift & goto parse_args

@rem 기타 Gradle/Maven 인자 누적
set "EXTRA_ARGS=!EXTRA_ARGS! %~1"
shift
goto parse_args

:end_parse

if "%ENV_VALUE%"=="" (
    echo ❌ [오류] 환경 파라미터가 필요합니다.
    echo 사용법: build_deploy.bat ^<환경명^> [옵션...]
    echo 예시  : build_deploy.bat dev
    echo        build_deploy.bat prod -Pport=8081
    exit /b 1
)

echo ================================================================
echo 🚀 빌드 및 배포 자동화 시작 (Windows: build_deploy.bat)
echo    - 배포 환경: %ENV_VALUE%
echo    - 배포 모드: Docker 컨테이너 배포 (방안 C)
echo ================================================================
echo.

@rem STEP 1. Git Pull
if "%SKIP_PULL%"=="true" (
    echo ⚠️  --no-pull 옵션에 따라 Git pull을 건너뜁니다.
) else if exist "%SCRIPT_DIR%.git" (
    echo ➡️  [1/2] Git 최신 코드 Pull 시도 중...
    git pull
    echo ✅  Git pull 완료
) else (
    echo ⚠️  Git 저장소가 아니므로 Git pull을 건너뜁니다.
)
echo.

@rem STEP 2. 빌드 도구 감지 및 배포 실행
echo ➡️  [2/2] 배포 빌드 및 서비스 설치 시작...

if exist "%SCRIPT_DIR%gradlew.bat" (
    echo 📦 Gradle 배포 패키지 빌드 시작 (clean package)...
    call "%SCRIPT_DIR%gradlew.bat" clean package -Penv=%ENV_VALUE% !EXTRA_ARGS!
    if !ERRORLEVEL! neq 0 (
        echo ❌ Gradle 빌드 실패
        exit /b 1
    )

    @rem ZIP 파일 탐색
    set "ZIP_FILE="
    for /f "delims=" %%F in ('dir /b /s /o-d "%SCRIPT_DIR%build\distributions\*.zip" "%SCRIPT_DIR%build\dist\*.zip" 2^>nul') do (
        if not defined ZIP_FILE set "ZIP_FILE=%%F"
    )

    if not defined ZIP_FILE (
        echo ❌ 빌드 결과물 ZIP 파일을 찾을 수 없습니다.
        exit /b 1
    )

    set "EXTRACT_DIR=%SCRIPT_DIR%build\distributions\unpacked"
    if exist "!EXTRACT_DIR!" rd /s /q "!EXTRACT_DIR!"
    mkdir "!EXTRACT_DIR!"

    echo 📂 배포 패키지 압축 해제 중: !ZIP_FILE!
    tar -xf "!ZIP_FILE!" -C "!EXTRACT_DIR!" 2>nul
    if !ERRORLEVEL! neq 0 (
        powershell -NoProfile -Command "Expand-Archive -LiteralPath '!ZIP_FILE!' -DestinationPath '!EXTRACT_DIR!' -Force"
    )

    @rem install_service.bat 실행
    set "INSTALL_SCRIPT="
    for /f "delims=" %%F in ('dir /b /s "%EXTRACT_DIR%\install_service.bat" 2^>nul') do (
        if not defined INSTALL_SCRIPT set "INSTALL_SCRIPT=%%F"
    )

    if defined INSTALL_SCRIPT (
        echo 🚀 Windows 서비스 설치 및 Docker 배포를 시작합니다...
        call "!INSTALL_SCRIPT!"
    ) else (
        echo ❌ install_service.bat 파일을 찾을 수 없습니다.
        exit /b 1
    )

) else if exist "%SCRIPT_DIR%mvnw.cmd" (
    echo 📦 Maven 배포 패키지 빌드 시작 (clean package)...
    call "%SCRIPT_DIR%mvnw.cmd" clean package -Denv=%ENV_VALUE% !EXTRA_ARGS!
    if !ERRORLEVEL! neq 0 (
        echo ❌ Maven 빌드 실패
        exit /b 1
    )

    set "ZIP_FILE="
    for /f "delims=" %%F in ('dir /b /s /o-d "%SCRIPT_DIR%target\*.zip" 2^>nul') do (
        if not defined ZIP_FILE set "ZIP_FILE=%%F"
    )

    if not defined ZIP_FILE (
        echo ❌ 빌드 결과물 ZIP 파일을 찾을 수 없습니다.
        exit /b 1
    )

    set "EXTRACT_DIR=%SCRIPT_DIR%target\unpacked"
    if exist "!EXTRACT_DIR!" rd /s /q "!EXTRACT_DIR!"
    mkdir "!EXTRACT_DIR!"

    echo 📂 배포 패키지 압축 해제 중: !ZIP_FILE!
    tar -xf "!ZIP_FILE!" -C "!EXTRACT_DIR!" 2>nul
    if !ERRORLEVEL! neq 0 (
        powershell -NoProfile -Command "Expand-Archive -LiteralPath '!ZIP_FILE!' -DestinationPath '!EXTRACT_DIR!' -Force"
    )

    set "INSTALL_SCRIPT="
    for /f "delims=" %%F in ('dir /b /s "%EXTRACT_DIR%\install_service.bat" 2^>nul') do (
        if not defined INSTALL_SCRIPT set "INSTALL_SCRIPT=%%F"
    )

    if defined INSTALL_SCRIPT (
        echo 🚀 Windows 서비스 설치 및 Docker 배포를 시작합니다...
        call "!INSTALL_SCRIPT!"
    ) else (
        echo ❌ install_service.bat 파일을 찾을 수 없습니다.
        exit /b 1
    )

) else (
    echo ❌ gradlew.bat 또는 mvnw.cmd 빌드 도구를 찾을 수 없습니다.
    exit /b 1
)

echo.
echo ================================================================
echo ✅ 빌드 및 배포 완료! (환경: %ENV_VALUE%)
echo ================================================================
exit /b 0

:show_help
echo ================================================================
echo 🚀 [build_deploy.bat] Windows 원스탑 빌드 및 배포 자동화
echo ================================================================
echo 사용법:
echo   build_deploy.bat ^<환경명^> [옵션...]
echo   build_deploy.bat -Penv=^<환경명^> [옵션...]
echo.
echo 주요 배포 환경: dev, prod, local, test, stage, qa
echo.
echo 주요 옵션:
echo   -Pport=^<포트^>     : 서비스 HTTP 포트 지정
echo   --no-pull          : 배포 전 Git pull 건너뛰기
echo   -h, --help         : 도움말 출력
echo ================================================================
exit /b 0
