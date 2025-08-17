# Используем официальный Python runtime как базовый образ
FROM python:3.11-slim

# Устанавливаем рабочую директорию в контейнере
WORKDIR /app

# Копируем файл requirements.txt в контейнер
COPY requirements.txt .

# Устанавливаем зависимости Python
RUN pip install --no-cache-dir -r requirements.txt

# Копируем код приложения в контейнер
COPY app.py .

# Создаем директорию для базы данных
RUN mkdir -p /app/data

# Настраиваем переменные окружения
ENV DATABASE_PATH=/app/data/mcp_stats.db
ENV FLASK_APP=app.py
ENV PYTHONUNBUFFERED=1

# Открываем порт 5000
EXPOSE 5000

# Команда для запуска приложения
CMD ["python", "app.py"]
