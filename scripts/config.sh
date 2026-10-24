#!/bin/bash

# Цвета для вывода
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# Путь к скриптам
export SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULES_DIR="$SCRIPTS_DIR/modules"
export REMNANODE_DIR="/opt/remnanode"
export REMNANODE_NODE_PORT="30100"
export REMNANODE_PANEL_IP_FILE="$REMNANODE_DIR/panel-ip"
export REMNANODE_PANEL_RULE_FILE="$REMNANODE_DIR/panel-access"
