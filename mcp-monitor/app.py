#!/usr/bin/env python3
"""
MCP Monitor Flask Application
Отслеживает использование MCP и отправляет ежедневные отчеты в Telegram
"""

from flask import Flask, request, jsonify
import sqlite3
import os
import logging
from datetime import datetime, timedelta
import threading
import time
import requests
from apscheduler.schedulers.background import BackgroundScheduler

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Конфигурация
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', 'YOUR_BOT_TOKEN')
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID', 'YOUR_CHAT_ID')
DATABASE_PATH = os.getenv('DATABASE_PATH', 'mcp_stats.db')

class MCPMonitor:
    def __init__(self):
        self.init_database()
        self.scheduler = BackgroundScheduler()
        self.scheduler.start()
        # Планируем ежедневные отчеты в 00:00 по Москве
        self.scheduler.add_job(
            func=self.send_daily_report,
            trigger="cron",
            hour=0,
            minute=0,
            timezone='Europe/Moscow'
        )
        logger.info("MCP Monitor инициализирован")

    def init_database(self):
        """Инициализация базы данных SQLite"""
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS mcp_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                tool_name TEXT NOT NULL,
                arguments TEXT,
                success BOOLEAN DEFAULT TRUE,
                response_length INTEGER DEFAULT 0,
                user_id TEXT DEFAULT 'default',
                session_id TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS daily_reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date DATE UNIQUE,
                total_requests INTEGER,
                successful_requests INTEGER,
                failed_requests INTEGER,
                top_tool TEXT,
                report_sent BOOLEAN DEFAULT FALSE
            )
        ''')
        
        conn.commit()
        conn.close()
        logger.info("База данных инициализирована")

    def log_mcp_event(self, tool_name, arguments=None, success=True, response_length=0, user_id='default', session_id=None):
        """Записывает событие MCP в базу данных"""
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO mcp_events (tool_name, arguments, success, response_length, user_id, session_id)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (tool_name, str(arguments), success, response_length, user_id, session_id))
        
        conn.commit()
        conn.close()
        logger.info(f"Записано MCP событие: {tool_name}")

    def get_daily_stats(self, date=None):
        """Получает статистику за день"""
        if date is None:
            date = datetime.now().date()
        
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        
        # Общая статистика
        cursor.execute('''
            SELECT 
                COUNT(*) as total_requests,
                SUM(CASE WHEN success THEN 1 ELSE 0 END) as successful_requests,
                SUM(CASE WHEN NOT success THEN 1 ELSE 0 END) as failed_requests
            FROM mcp_events 
            WHERE DATE(timestamp) = ?
        ''', (date,))
        
        stats = cursor.fetchone()
        
        # Топ инструментов
        cursor.execute('''
            SELECT tool_name, COUNT(*) as count
            FROM mcp_events 
            WHERE DATE(timestamp) = ?
            GROUP BY tool_name
            ORDER BY count DESC
            LIMIT 5
        ''', (date,))
        
        top_tools = cursor.fetchall()
        
        # Статистика по часам
        cursor.execute('''
            SELECT 
                strftime('%H', timestamp) as hour,
                COUNT(*) as count
            FROM mcp_events 
            WHERE DATE(timestamp) = ?
            GROUP BY hour
            ORDER BY hour
        ''', (date,))
        
        hourly_stats = cursor.fetchall()
        
        conn.close()
        
        return {
            'date': str(date),
            'total_requests': stats[0] or 0,
            'successful_requests': stats[1] or 0,
            'failed_requests': stats[2] or 0,
            'top_tools': top_tools,
            'hourly_stats': hourly_stats
        }

    def send_telegram_message(self, message):
        """Отправляет сообщение в Telegram"""
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = {
            'chat_id': TELEGRAM_CHAT_ID,
            'text': message,
            'parse_mode': 'Markdown'
        }
        
        try:
            response = requests.post(url, json=data)
            if response.status_code == 200:
                logger.info("Сообщение отправлено в Telegram")
                return True
            else:
                logger.error(f"Ошибка отправки в Telegram: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Ошибка отправки в Telegram: {e}")
            return False

    def format_daily_report(self, stats):
        """Форматирует ежедневный отчет"""
        date = stats['date']
        total = stats['total_requests']
        successful = stats['successful_requests']
        failed = stats['failed_requests']
        
        if total == 0:
            return f"📊 *MCP Отчет за {date}*\n\n😴 Сегодня MCP не использовался"
        
        report = f"📊 *MCP Отчет за {date}*\n\n"
        report += f"🔢 Всего запросов: *{total}*\n"
        report += f"✅ Успешных: *{successful}*\n"
        
        if failed > 0:
            report += f"❌ Ошибок: *{failed}*\n"
        
        # Топ инструментов
        if stats['top_tools']:
            report += f"\n🔧 *Топ инструментов:*\n"
            for tool, count in stats['top_tools']:
                emoji = {
                    'get_user_repositories': '📁',
                    'get_issues': '🐛',
                    'create_repository': '🆕'
                }.get(tool, '🔧')
                report += f"{emoji} {tool}: *{count}*\n"
        
        # Активность по часам
        if stats['hourly_stats']:
            report += f"\n⏰ *Активность по часам:*\n"
            for hour, count in stats['hourly_stats'][-5:]:  # Последние 5 самых активных часов
                report += f"{hour}:00 - *{count}* запросов\n"
        
        report += f"\n🤖 Мониторинг работает 24/7"
        
        return report

    def send_daily_report(self):
        """Отправляет ежедневный отчет"""
        yesterday = (datetime.now() - timedelta(days=1)).date()
        today = datetime.now().date()
        
        # Отчет за вчера (если есть данные)
        yesterday_stats = self.get_daily_stats(yesterday)
        if yesterday_stats['total_requests'] > 0:
            report = self.format_daily_report(yesterday_stats)
            self.send_telegram_message(report)
        
        # Краткий отчет за сегодня
        today_stats = self.get_daily_stats(today)
        if today_stats['total_requests'] > 0:
            report = f"📊 *Сегодня ({today})*\n"
            report += f"🔢 Запросов: *{today_stats['total_requests']}*\n"
            if today_stats['top_tools']:
                top_tool = today_stats['top_tools'][0]
                report += f"🔧 Топ инструмент: *{top_tool[0]}* ({top_tool[1]})"
            self.send_telegram_message(report)

# Инициализируем монитор
monitor = MCPMonitor()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'database': DATABASE_PATH
    })

@app.route('/mcp/event', methods=['POST'])
def log_mcp_event():
    """Endpoint для записи событий MCP"""
    try:
        data = request.get_json()
        
        tool_name = data.get('tool_name')
        arguments = data.get('arguments', {})
        success = data.get('success', True)
        response_length = data.get('response_length', 0)
        user_id = data.get('user_id', 'default')
        session_id = data.get('session_id')
        
        if not tool_name:
            return jsonify({'error': 'tool_name is required'}), 400
        
        monitor.log_mcp_event(
            tool_name=tool_name,
            arguments=arguments,
            success=success,
            response_length=response_length,
            user_id=user_id,
            session_id=session_id
        )
        
        return jsonify({
            'status': 'success',
            'message': 'Event logged successfully'
        })
        
    except Exception as e:
        logger.error(f"Ошибка записи события: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/stats', methods=['GET'])
def get_stats():
    """Endpoint для получения статистики"""
    date_str = request.args.get('date')
    
    if date_str:
        try:
            date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return jsonify({'error': 'Invalid date format. Use YYYY-MM-DD'}), 400
    else:
        date = datetime.now().date()
    
    stats = monitor.get_daily_stats(date)
    return jsonify(stats)

@app.route('/report/send', methods=['POST'])
def send_manual_report():
    """Endpoint для ручной отправки отчета"""
    try:
        monitor.send_daily_report()
        return jsonify({
            'status': 'success',
            'message': 'Report sent successfully'
        })
    except Exception as e:
        logger.error(f"Ошибка отправки отчета: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # Отправляем стартовое сообщение
    if TELEGRAM_BOT_TOKEN != 'YOUR_BOT_TOKEN' and TELEGRAM_CHAT_ID != 'YOUR_CHAT_ID':
        monitor.send_telegram_message("🚀 *MCP Monitor запущен!*\n\nМониторинг активности начат.\nЕжедневные отчеты в 00:00 МСК.")
    
    app.run(host='0.0.0.0', port=5000, debug=False)
