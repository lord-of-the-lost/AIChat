#!/bin/bash

# Скрипт для запуска MCP Docker сервиса

echo "🚀 Запуск MCP Docker сервиса..."

# Переходим в директорию mcp-docker
cd "$(dirname "$0")/mcp-docker"

# Проверяем существование виртуального окружения
if [ ! -d "venv" ]; then
    echo "📦 Создаем виртуальное окружение..."
    python3 -m venv venv
fi

# Активируем виртуальное окружение
echo "🔧 Активируем виртуальное окружение..."
source venv/bin/activate

# Устанавливаем зависимости
echo "📚 Устанавливаем зависимости..."
pip install -r requirements.txt

# Запускаем сервис
echo "🚀 Запускаем MCP Docker сервис на порту 5002..."
python app.py
