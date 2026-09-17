# 🚀 Spring Boot Build & Deploy Platform

[English](README_EN.md) | [한국어](README.md)

> **A centralized build and deployment automation platform for Spring Boot applications.**  
> Eliminate the need to copy boilerplate deployment scripts and Dockerfiles across individual repositories.  
> Both the **Gradle Plugin** and **Maven Plugin** are maintained under a Single Source of Truth (SSOT), enabling any Spring Boot project to establish a standardized deployment environment with **just one line of configuration**. ✨

---

## 🌟 Core Values: Why Use Plugins?

1. **📦 Zero-Copy Infrastructure (Zero Configuration)**:
    - No need to maintain duplicated `scripts/` or `docker/` directories in each repository.
    - Standard deployment scripts (service installation, daemon start/stop, status check) and `Dockerfile` are bundled within the plugin JAR and assembled into distribution archives (`.zip`) automatically.
2. **🧩 File-Level `@Override` Mechanism (Inheritance Model)**:
    - Need to tune JVM arguments or customize a startup script for a specific service? Simply create a local file with the same path (e.g., `scripts/service/start.sh`).
    - The plugin **automatically prioritizes your local file (@Override)** while continuing to pull all other unmodified scripts from the default plugin templates.
3. **🔄 Single Source of Truth (SSOT) for Gradle & Maven**:
    - The repository root `/scripts` and `/docker` folders act as the single authoritative source.
    - Both plugins pull assets directly from the root templates during build, completely eliminating script drift.
    - A single `./gradlew publishAllPlugins` command publishes updates simultaneously to **Gradle Plugin Portal** and **Maven Central**.

---

## 🔌 Distribution Plugins

Apply the appropriate plugin according to your project's build tool:

| Build Tool | Plugin Module                                 | Repository           | Documentation                                                    |
| :--------- | :-------------------------------------------- | :------------------- | :--------------------------------------------------------------- |
| **Gradle** | `io.github.mj-youn.distribution`              | Gradle Plugin Portal | [**Gradle Plugin README**](distribution-gradle-plugin/README.md) |
| **Maven**  | `io.github.mj-youn:distribution-maven-plugin` | Maven Central        | [**Maven Plugin README**](distribution-maven-plugin/README.md)   |

### 💻 Quick Start (One-Line Setup)

#### 🐘 Gradle Project (`build.gradle`)

```groovy
plugins {
    id 'io.github.mj-youn.distribution' version '3.0.0'
}
```

- **Generate Distribution Package**:
    ```bash
    ./gradlew package -Penv=dev    # Development distribution zip
    ./gradlew package -Penv=prod   # Production distribution zip
    ```
- **View Help & Guide**:
    ```bash
    ./gradlew distHelp             # Display plugin help in console
    ```

#### 🪶 Maven Project (`pom.xml`)

```xml
<build>
    <plugins>
        <plugin>
            <groupId>io.github.mj-youn</groupId>
            <artifactId>distribution-maven-plugin</artifactId>
            <version>3.0.0</version>
            <executions>
                <execution>
                    <goals><goal>package</goal></goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

- **Generate Distribution Package**:
    ```bash
    mvn clean package -Denv=dev    # Development distribution zip
    mvn clean package -Denv=prod   # Production distribution zip
    ```
- **View Help & Guide**:
    ```bash
    mvn distribution:help          # Display plugin help in console (or mvn distribution:distHelp)
    ```

---

### 💡 Plugin Help & Command Reference

You can inspect all available tasks, goals, environment options, and command examples directly from your terminal:

#### 🐘 Gradle Environment

To prevent naming collisions with Gradle's built-in `help` task, the plugin provides a dedicated **`distHelp`** task:

```bash
# Display distribution guide and supported commands
./gradlew distHelp

# List all tasks provided by the distribution group
./gradlew tasks --group=distribution
```

#### 🪶 Maven Environment

Supports standard `prefix:goal` notation. For convenience, both `help` and `distHelp` aliases are supported:

```bash
mvn distribution:help
# Or Gradle-style alias
mvn distribution:distHelp
```

---

### 🏷️ `appName` Configuration (Optional)

The `appName` option serves as the **official identifier** for your service across server deployments and runtime operations.

#### 1) Default Behavior

- **Optional**: Works out of the box if omitted.
- Defaults:
    - **Gradle**: `rootProject.name` from `settings.gradle`
    - **Maven**: `<artifactId>` from `pom.xml`

#### 2) When Should You Set `appName`?

We recommend explicitly defining a concise, lowercase identifier when:

- The repository name contains uppercase or special characters (e.g., `LGUplus-HDRMS-WEB` ➡️ `appName = 'hdrms'`).
- You want consistent naming across infrastructure:
    - 🐧 **Linux Systemd Service**: `/etc/systemd/system/{appName}.service` (`systemctl start {appName}`)
    - 📁 **Default Log Directory**: `/log/{appName}` (e.g., `/log/hdrms`)
    - 🐳 **Docker Image Tag**: `{appName}:{version}` (e.g., `hdrms:0.1.0`)
    - 🐚 **Process Console Output**: `🚀 Starting [{appName}] service...`

#### 3) ⚠️ Note on Changing `appName`

> Linux Systemd identifies services by file name (`{appName}.service`). Changing `appName` on an already deployed server may register it as a **new distinct service**. It is best to finalize your service name before the initial production deployment.

---

## 🚀 One-Stop Build & Auto Deployment (`deployService` / `distribution:deploy`)

> For servers where source code resides locally, this feature automates the tedious sequence of **"Build ➡️ Unzip ➡️ Execute Installer"** in a **single command**.

### 🔄 Execution Flow

```text
[1/3] 🔨 Package         → Build environment-specific ZIP package (Jar + Scripts + Dockerfile)
[2/3] 📦 AUTO Unzip      → Extract ZIP to a temporary directory inside the build output folder
[3/3] 🚀 Start Service   → Execute deploy/install_service.sh (Registers daemon and starts application)
```

### 💻 Commands

- **Gradle**:
    ```bash
    ./gradlew deployService -Penv=dev
    ./gradlew deployService -Penv=prod
    ```
- **Maven**:
    ```bash
    mvn distribution:deploy -Denv=dev
    mvn distribution:deploy -Denv=prod
    ```

---

## 📦 Build & Deployment Strategies

### 🐳 Docker Deployment 1: Local Build (Standard)

**"Local Build -> Image Tar Export -> Server Transfer -> Load & Run"**  
No build tools or source code required on production servers.

1. **Build**:
    - Gradle: `./gradlew packageDocker -Penv=prod`
    - Maven: `mvn distribution:package-docker -Denv=prod`
    - Output: `build/dist/{APP_NAME}-docker-prod.zip` (contains `image.tar`, `docker-compose.yml`, `config/`, scripts)
2. **Deploy**:
    ```bash
    scp build/dist/{APP_NAME}-docker-prod.zip user@server:/home/user/
    unzip {APP_NAME}-docker-prod.zip -d deploy
    cd deploy
    sudo ./deploy/install_service.sh
    ```

### 🐳 Docker Deployment 2: Registry (Push & Pull)

**"Build -> Registry Push -> Server Pull -> Run"**  
Leverages remote registries such as Docker Hub, ECR, or GCR.

1. **Build & Push**:
    - Gradle: `./gradlew dockerBuildRemote -Penv=prod -PdockerRegistry=my-registry.com/repo`
    - Maven: `mvn distribution:docker-build-remote -Denv=prod -DdockerRegistry=my-registry.com/repo`
2. **Deploy on Server**:
   Deploy only the generated `docker-dist/` directory:
    ```bash
    cd docker-dist
    sudo ./deploy/install_service.sh
    ```

### 🖥️ Bare-Metal / VM Deployment (Legacy)

Deploys directly on servers with JDK installed (no Docker required).

1. **Build**:
    - Gradle: `./gradlew package -Penv=prod`
    - Maven: `mvn clean package -Denv=prod`
2. **Deploy on Server**:
    ```bash
    unzip {APP_NAME}-*.zip -d {APP_NAME}
    cd {APP_NAME}
    sudo ./deploy/install_service.sh
    ```

---

## 📂 Scripts Directory Architecture

The `/scripts` directory is organized into distinct subdirectories based on responsibility:

- **`scripts/deploy/`** (Installation & Removal):
    - `install_service.sh`: Installs service and registers Systemd/SysVinit daemon.
    - `uninstall_service.sh`: Stops and unregisters the service.
- **`scripts/service/`** (Runtime Daemon Control):
    - `start.sh`: Starts background service process.
    - `stop.sh`: Graceful shutdown with automatic force-kill fallback.
    - `status.sh`: Displays running state, PID, port, and log file path.
    - `cron/`: Scheduled cron jobs and health-check scripts.
- **`scripts/common/`** (Shared Utilities):
    - `bootstrap.sh`: Environment loader and fallback helper.
    - `utils.sh`: Color logging and safe directory validation utilities.

---

## 🎨 Advanced Configuration: Environment Profiles & Overlay

Configuration files (`config`) and scripts (`scripts`) follow an **"Overlay Strategy"**:

| Path                                        | Purpose                                 | Priority                                          |
| :------------------------------------------ | :-------------------------------------- | :------------------------------------------------ |
| `config.profiles/prod/application-prod.yml` | Production Application Config           | 🥇 Priority 1 (Overlays `config/application.yml`) |
| `config.profiles/prod/log4j2-prod.yml`      | Production Logging Config               | 🥇 Priority 1 (Overlays `config/log4j2.yml`)      |
| `config/application.yml`                    | Common Default Config                   | 🥈 Priority 2                                     |
| `config/log4j2.yml`                         | Common Default Logging                  | 🥈 Priority 2                                     |
| `scripts/prod/.env`                         | Production Script Environment Variables | 🥇 Priority 1 (Overlays package root `.env`)      |
| `scripts/.env`                              | Common Default Variables                | 🥈 Priority 2                                     |

---

## ⚙️ Runtime Environment Variables (`.env`)

Control JVM memory tuning, system properties, and Spring Boot arguments without modifying script files.

### 📋 Supported Environment Variables

| Category               | Variable              | Default                | Description & Example                                                      |
| :--------------------- | :-------------------- | :--------------------- | :------------------------------------------------------------------------- |
| **JVM Memory**         | `JVM_XMS`             | _(empty)_              | Initial heap size (`-Xms1024m`, `-Xms2g`)                                  |
|                        | `JVM_XMX`             | _(empty)_              | Maximum heap size (`-Xmx2048m`, `-Xmx4g`)                                  |
| **JVM Options**        | `EXTRA_JAVA_OPTS`     | _(empty)_              | GC algorithm, encoding, timezone (`"-XX:+UseG1GC -Dfile.encoding=UTF-8"`)  |
| **Spring Boot Args**   | `APP_ARGS`            | _(empty)_              | Command-line arguments (`"--server.port=9090 --custom.flag=true"`)         |
| **Process Control**    | `SERVER_PORT`         | `8080` (auto-detected) | Service port (automatically parsed from `application.yml`)                 |
|                        | `LOG_PATH`            | `{PROJECT_ROOT}/log`   | Log directory path                                                         |
|                        | `PID_FILE`            | `bin/application.pid`  | PID tracking file path                                                     |
|                        | `STOP_TIMEOUT`        | `10`                   | Graceful shutdown timeout (seconds)                                        |
| **Docker / Container** | `APP_UID` / `APP_GID` | `1000` / `1000`        | Linux user UID/GID inside container                                        |
|                        | `TZ`                  | `Asia/Seoul`           | Container system timezone                                                  |
| **Extra Directories**  | `EXTRA_DIRS`          | _(empty)_              | Additional folders to bundle into package root (`EXTRA_DIRS="flags data"`) |

---

### 📁 Extra Directories Replication (`EXTRA_DIRS` / `extraDirs`)

Bundle custom non-standard folders (e.g., `flags/`, `data/`, `uploads/`) into the distribution ZIP package and final installation destination:

#### 1. Via `.env` (Recommended)

```bash
EXTRA_DIRS="flags data uploads"
```

#### 2. Via Build Script

- **Gradle (`build.gradle`)**:
    ```groovy
    distribution {
        appName = 'my-service'
        extraDirs = ['flags', 'data']
    }
    ```
- **Maven (`pom.xml`)**:
    ```xml
    <configuration>
      <appName>${project.artifactId}</appName>
      <extraDirs>flags data</extraDirs>
    </configuration>
    ```

---

## 🛠️ Maintainer Guide

For architecture design, SSOT asset synchronization, local verification, and simultaneous multi-portal publication (`publishAllPlugins`), please refer to:

👉 [**Developer & Maintainer Guide (DEVELOPER_GUIDE.md)**](DEVELOPER_GUIDE.md)
