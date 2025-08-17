# MCP Monitor

Система мониторинга использования MCP с ежедневными отчетами в Telegram.

## 🚀 Быстрый старт

### 1. Настройка Telegram бота

1. Напишите [@BotFather](https://t.me/BotFather) в Telegram
2. Создайте нового бота: `/newbot`
3. Получите токен (формат: `123456789:XXXXXX`)
4. Получите свой Chat ID у [@userinfobot](https://t.me/userinfobot)

### 2. Настройка приложения

```bash
# Копируем пример конфигурации
cp env-example .env

# Редактируем файл .env
nano .env
```

Заполните:
```
TELEGRAM_BOT_TOKEN=ваш_токен_бота
TELEGRAM_CHAT_ID=ваш_chat_id
```

### 3. Запуск в Docker

```bash
# Сборка и запуск
docker-compose up -d

# Проверка статуса
docker-compose logs -f

# Остановка
docker-compose down
```

## 📊 API Endpoints

### Логирование событий MCP
```bash
POST /mcp/event
Content-Type: application/json

{
  "tool_name": "get_user_repositories",
  "arguments": {"page": 1},
  "success": true,
  "response_length": 1024,
  "user_id": "user123",
  "session_id": "session456"
}
```

### Получение статистики
```bash
GET /stats?date=2024-08-17
```

### Ручная отправка отчета
```bash
POST /report/send
```

### Health check
```bash
GET /health
```

## 🕒 Автоматические отчеты

- **Время**: Каждый день в 23:45 МСК
- **Содержание**: Статистика за день, топ инструментов, активность по часам
- **Канал**: Telegram

## 📈 Пример отчета

```
📊 MCP Отчет за 2024-08-17

🔢 Всего запросов: 15
✅ Успешных: 14
❌ Ошибок: 1

🔧 Топ инструментов:
📁 get_user_repositories: 8
🐛 get_issues: 4
🆕 create_repository: 3

⏰ Активность по часам:
14:00 - 5 запросов
16:00 - 3 запроса
18:00 - 7 запросов

🤖 Мониторинг работает 24/7
```

## 🔧 Интеграция с iOS

В вашем iOS приложении добавьте отправку статистики после каждого MCP вызова.

## 🛠 Разработка

```bash
# Локальный запуск
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

## 📁 Структура

```
mcp-monitor/
├── app.py              # Основное приложение Flask
├── requirements.txt    # Python зависимости
├── Dockerfile         # Docker образ
├── docker-compose.yml # Docker Compose конфигурация
├── env-example        # Пример переменных окружения
└── data/             # База данных SQLite (создается автоматически)
```
