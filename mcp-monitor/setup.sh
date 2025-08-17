#!/bin/bash

echo "🚀 Настройка MCP Monitor"
echo "======================="

# Проверяем, что Docker установлен
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен. Установите Docker и повторите попытку."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose не установлен. Установите Docker Compose и повторите попытку."
    exit 1
fi

echo "✅ Docker и Docker Compose найдены"

# Создаем директорию для данных
mkdir -p data

# Проверяем наличие .env файла
if [ ! -f .env ]; then
    echo "📝 Создаем файл .env..."
    cp env-example .env
    
    echo ""
    echo "🔧 Необходимо настроить Telegram бота:"
    echo "1. Перейдите к @BotFather в Telegram"
    echo "2. Создайте нового бота: /newbot"
    echo "3. Получите токен бота"
    echo "4. Перейдите к @userinfobot для получения вашего Chat ID"
    echo ""
    
    read -p "Введите токен Telegram бота: " BOT_TOKEN
    read -p "Введите ваш Chat ID: " CHAT_ID
    
    # Обновляем .env файл
    sed -i.bak "s/your_bot_token_here/$BOT_TOKEN/" .env
    sed -i.bak "s/your_chat_id_here/$CHAT_ID/" .env
    rm .env.bak
    
    echo "✅ Файл .env настроен"
else
    echo "✅ Файл .env уже существует"
fi

echo ""
echo "🏗 Сборка Docker образа..."
docker-compose build

echo ""
echo "🚀 Запуск MCP Monitor..."
docker-compose up -d

echo ""
echo "⏳ Ждем запуска сервиса..."
sleep 5

# Проверяем статус
if docker-compose ps | grep -q "Up"; then
    echo "✅ MCP Monitor успешно запущен!"
    echo ""
    echo "📊 Проверка работы:"
    echo "curl http://localhost:5001/health"
    echo ""
    echo "📱 Интеграция с iOS:"
    echo "Убедитесь, что в iOS приложении настроен URL: http://localhost:5001"
    echo ""
    echo "📋 Управление:"
    echo "docker-compose logs -f    # Просмотр логов"
    echo "docker-compose down       # Остановка"
    echo "docker-compose restart    # Перезапуск"
    echo ""
    echo "🕘 Отчеты будут приходить каждый день в 23:45 МСК"
else
    echo "❌ Ошибка запуска. Проверьте логи:"
    echo "docker-compose logs"
fi
