#!/usr/bin/env python3
"""
MCP Docker Service - выполнение кода в Docker контейнерах (исправленная версия)
"""

from flask import Flask, request, jsonify
import subprocess
import tempfile
import os
import time
import logging
import json

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

def run_docker_command(cmd, timeout=30):
    """Выполнение Docker команды через subprocess"""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return {
            "success": result.returncode == 0,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "stdout": "",
            "stderr": "Timeout expired",
            "returncode": -1
        }
    except Exception as e:
        return {
            "success": False,
            "stdout": "",
            "stderr": str(e),
            "returncode": -1
        }

def test_docker():
    """Тест подключения к Docker"""
    result = run_docker_command(["docker", "version", "--format", "json"])
    if result["success"]:
        try:
            version_info = json.loads(result["stdout"])
            app.logger.info(f"🐳 Docker версия: {version_info.get('Server', {}).get('Version', 'неизвестно')}")
            return True
        except:
            pass
    return False

@app.route('/health', methods=['GET'])
def health_check():
    """Проверка здоровья сервиса"""
    if test_docker():
        return jsonify({
            "status": "healthy",
            "docker": "available",
            "timestamp": time.time()
        })
    else:
        return jsonify({
            "status": "error", 
            "message": "Docker недоступен"
        }), 500

@app.route('/execute/swift', methods=['POST'])
def execute_swift():
    """Выполнение Swift кода в Docker"""
    try:
        data = request.get_json()
        if not data or 'code' not in data:
            return jsonify({
                "success": False,
                "error": "Код не предоставлен"
            }), 400
        
        code = data['code']
        timeout = data.get('timeout', 30)
        
        app.logger.info(f"🚀 Выполняем Swift код (timeout: {timeout}s)")
        app.logger.info(f"📝 Код:\n{code}")
        
        # Создаем временный файл
        with tempfile.NamedTemporaryFile(mode='w', suffix='.swift', delete=False) as f:
            f.write(code)
            temp_file = f.name
        
        try:
            # Получаем абсолютный путь к директории
            temp_dir = os.path.dirname(os.path.abspath(temp_file))
            filename = os.path.basename(temp_file)
            
            app.logger.info(f"📁 Монтируем {temp_dir} в контейнер")
            
            # Выполняем Swift код в Docker
            cmd = [
                "docker", "run", "--rm",
                "-v", f"{temp_dir}:/app",
                "-w", "/app",
                "swift:5.9",
                "swift", filename
            ]
            
            result = run_docker_command(cmd, timeout)
            
            # Удаляем временный файл
            os.unlink(temp_file)
            
            if result["success"]:
                return jsonify({
                    "success": True,
                    "output": result["stdout"],
                    "error": result["stderr"],
                    "execution_time": time.time()
                })
            else:
                return jsonify({
                    "success": False,
                    "output": result["stdout"],
                    "error": result["stderr"],
                    "execution_time": time.time()
                })
                
        except Exception as e:
            # Удаляем временный файл в случае ошибки
            if os.path.exists(temp_file):
                os.unlink(temp_file)
            raise e
            
    except Exception as e:
        app.logger.error(f"❌ Ошибка выполнения Swift кода: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

if __name__ == '__main__':
    print("🚀 Запускаем MCP Docker Service на порту 5002")
    app.run(host='0.0.0.0', port=5002, debug=True)
