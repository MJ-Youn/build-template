#!/bin/bash

APP_NAME="@appName@"

PID=$(ps -ef | grep "-Dapp.name=$APP_NAME" | grep -v grep | awk '{print $2}')

if [ -n "$PID" ]; then
    echo "Service $APP_NAME is running (PID: $PID)"
    exit 0
else
    echo "Service $APP_NAME is NOT running"
    exit 1
fi
