#!/usr/bin/env python3
"""
MCP Docker Service - выполнение кода в Docker контейнерах
"""

from flask import Flask, request, jsonify
import docker
import tempfile
import os
import time
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Инициализация Docker клиента
def init_docker_client():
    try:
        # Пробуем разные способы подключения к Docker
        import os
        
        # Способ 1: стандартное подключение
        try:
            client = docker.from_env()
            # Проверяем подключение
            info = client.info()
            app.logger.info("🐳 Docker клиент инициализирован (стандартный)")
            app.logger.info(f"📋 Docker версия: {info.get('ServerVersion', 'неизвестно')}")
            return client
        except Exception as e1:
            app.logger.warning(f"⚠️ Стандартное подключение не удалось: {e1}")
        
        # Способ 2: через пользовательский socket
        try:
            user_socket = f"unix://{os.path.expanduser('~')}/.docker/run/docker.sock"
            client = docker.DockerClient(base_url=user_socket)
            # Проверяем подключение
            info = client.info()
            app.logger.info(f"🐳 Docker клиент инициализирован (пользовательский socket: {user_socket})")
            app.logger.info(f"📋 Docker версия: {info.get('ServerVersion', 'неизвестно')}")
            return client
        except Exception as e2:
            app.logger.warning(f"⚠️ Пользовательский socket не удался: {e2}")
        
        # Способ 3: через TCP (если настроен)
        try:
            client = docker.DockerClient(base_url="tcp://localhost:2376")
            client.ping()
            app.logger.info("🐳 Docker клиент инициализирован (TCP)")
            return client
        except Exception as e3:
            app.logger.warning(f"⚠️ TCP подключение не удалось: {e3}")
        
        app.logger.error("❌ Все способы подключения к Docker не удались")
        return None
        
    except Exception as e:
        app.logger.error(f"❌ Критическая ошибка инициализации Docker: {e}")
        return None

docker_client = init_docker_client()

@app.route('/health', methods=['GET'])
def health_check():
    """Проверка здоровья сервиса"""
    if docker_client is None:
        return jsonify({"status": "error", "message": "Docker недоступен"}), 500
    
    try:
        # Проверяем что Docker работает
        docker_client.ping()
        return jsonify({
            "status": "healthy",
            "docker": "available",
            "timestamp": time.time()
        })
    except Exception as e:
        return jsonify({
            "status": "error", 
            "message": f"Docker ping failed: {str(e)}"
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
            # Создаем временную директорию для монтирования
            temp_dir = os.path.dirname(temp_file)
            container_file = f"/app/{os.path.basename(temp_file)}"
            
            app.logger.info(f"📁 Монтируем {temp_dir} в контейнер")
            
            # Запускаем Swift в Docker контейнере
            result = docker_client.containers.run(
                image="swift:5.9",
                command=f"swift {container_file}",
                volumes={temp_dir: {'bind': '/app', 'mode': 'rw'}},
                working_dir="/app",
                remove=True,
                network_mode="none",  # Изолируем сеть
                detach=False,
                stdout=True,
                stderr=True
            )
            
            app.logger.info("✅ Контейнер завершил работу")
            
            # Парсим результат
            if isinstance(result, bytes):
                output = result.decode('utf-8')
                success = True
                error = ""
            else:
                output = str(result)
                success = True
                error = ""
                
        except docker.errors.ContainerError as e:
            app.logger.error(f"❌ Ошибка контейнера: {e}")
            success = False
            output = ""
            # Получаем stderr из исключения
            stderr_text = ""
            if hasattr(e, 'stderr') and e.stderr:
                stderr_text = e.stderr.decode('utf-8') if isinstance(e.stderr, bytes) else str(e.stderr)
            error = f"Ошибка выполнения: {stderr_text or str(e)}"
            
        except Exception as e:
            app.logger.error(f"❌ Общая ошибка: {e}")
            success = False
            output = ""
            error = f"Ошибка Docker: {str(e)}"
            
        finally:
            # Удаляем временный файл
            try:
                os.unlink(temp_file)
            except:
                pass
        
        return jsonify({
            "success": success,
            "output": output,
            "error": error,
            "language": "swift"
        })
        
    except Exception as e:
        app.logger.error(f"❌ Критическая ошибка: {e}")
        return jsonify({
            "success": False,
            "error": f"Серверная ошибка: {str(e)}"
        }), 500

@app.route('/execute/python', methods=['POST'])
def execute_python():
    """Выполнение Python кода в Docker"""
    try:
        data = request.get_json()
        code = data.get('code', '')
        timeout = data.get('timeout', 30)
        
        app.logger.info(f"🐍 Выполняем Python код")
        
        # Аналогично Swift, но для Python
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(code)
            temp_file = f.name
        
        try:
            temp_dir = os.path.dirname(temp_file)
            container_file = f"/app/{os.path.basename(temp_file)}"
            
            result = docker_client.containers.run(
                image="python:3.11-slim",
                command=f"python {container_file}",
                volumes={temp_dir: {'bind': '/app', 'mode': 'rw'}},
                working_dir="/app",
                remove=True,
                network_mode=None,
                timeout=timeout,
                capture_output=True,
                text=True
            )
            
            success = True
            output = str(result)
            error = ""
            
        except docker.errors.ContainerError as e:
            success = False
            output = ""
            error = f"Ошибка выполнения: {e.stderr.decode('utf-8') if e.stderr else str(e)}"
            
        finally:
            try:
                os.unlink(temp_file)
            except:
                pass
        
        return jsonify({
            "success": success,
            "output": output,
            "error": error,
            "language": "python"
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": f"Серверная ошибка: {str(e)}"
        }), 500

if __name__ == '__main__':
    print("🚀 Запускаем MCP Docker Service на порту 5002")
    app.run(host='0.0.0.0', port=5002, debug=True)
