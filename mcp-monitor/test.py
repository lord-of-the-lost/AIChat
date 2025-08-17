#!/usr/bin/env python3
"""
Тестовый скрипт для проверки MCP Monitor
"""

import requests
import json
import time
from datetime import datetime

BASE_URL = "http://localhost:5001"

def test_health():
    """Тест health check"""
    try:
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code == 200:
            print("✅ Health check пройден")
            print(f"📄 Ответ: {response.json()}")
            return True
        else:
            print(f"❌ Health check провален: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Ошибка подключения: {e}")
        return False

def test_mcp_event():
    """Тест отправки MCP события"""
    event_data = {
        "tool_name": "get_user_repositories",
        "arguments": {"page": 1, "perPage": 30},
        "success": True,
        "response_length": 1024,
        "user_id": "test_user",
        "session_id": "test_session_123"
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/mcp/event",
            json=event_data,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            print("✅ MCP событие записано")
            print(f"📄 Ответ: {response.json()}")
            return True
        else:
            print(f"❌ Ошибка записи события: {response.status_code}")
            print(f"📄 Ответ: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Ошибка отправки события: {e}")
        return False

def test_get_stats():
    """Тест получения статистики"""
    today = datetime.now().strftime('%Y-%m-%d')
    
    try:
        response = requests.get(f"{BASE_URL}/stats?date={today}")
        if response.status_code == 200:
            print("✅ Статистика получена")
            stats = response.json()
            print(f"📊 Статистика за {today}:")
            print(f"   Всего запросов: {stats['total_requests']}")
            print(f"   Успешных: {stats['successful_requests']}")
            print(f"   Ошибок: {stats['failed_requests']}")
            if stats['top_tools']:
                print(f"   Топ инструментов: {stats['top_tools']}")
            return True
        else:
            print(f"❌ Ошибка получения статистики: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Ошибка получения статистики: {e}")
        return False

def test_manual_report():
    """Тест ручной отправки отчета"""
    try:
        response = requests.post(f"{BASE_URL}/report/send")
        if response.status_code == 200:
            print("✅ Отчет отправлен")
            print(f"📄 Ответ: {response.json()}")
            return True
        else:
            print(f"❌ Ошибка отправки отчета: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Ошибка отправки отчета: {e}")
        return False

def simulate_mcp_activity():
    """Имитация активности MCP"""
    print("\n🎭 Имитация активности MCP...")
    
    events = [
        {"tool_name": "get_user_repositories", "arguments": {"page": 1}, "success": True, "response_length": 2048},
        {"tool_name": "get_issues", "arguments": {"owner": "test", "repo": "app"}, "success": True, "response_length": 1536},
        {"tool_name": "create_repository", "arguments": {"name": "test-repo"}, "success": True, "response_length": 512},
        {"tool_name": "get_user_repositories", "arguments": {"page": 2}, "success": False, "response_length": 128},
        {"tool_name": "get_issues", "arguments": {"owner": "test", "repo": "web"}, "success": True, "response_length": 896},
    ]
    
    for i, event in enumerate(events, 1):
        print(f"📤 Отправка события {i}/5: {event['tool_name']}")
        
        response = requests.post(
            f"{BASE_URL}/mcp/event",
            json=event,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            print(f"   ✅ Успешно")
        else:
            print(f"   ❌ Ошибка: {response.status_code}")
        
        time.sleep(1)  # Небольшая пауза между запросами

if __name__ == "__main__":
    print("🧪 Тестирование MCP Monitor")
    print("=" * 30)
    
    # Проверяем, что сервис запущен
    if not test_health():
        print("\n❌ Сервис недоступен. Убедитесь, что MCP Monitor запущен:")
        print("docker-compose up -d")
        exit(1)
    
    print("\n" + "=" * 30)
    
    # Имитируем активность
    simulate_mcp_activity()
    
    print("\n" + "=" * 30)
    
    # Тестируем статистику
    test_get_stats()
    
    print("\n" + "=" * 30)
    
    # Тестируем отправку отчета (если настроен Telegram)
    print("\n📬 Тест отправки отчета в Telegram...")
    test_manual_report()
    
    print("\n✅ Тестирование завершено!")
