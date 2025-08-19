# AI Chat - macOS Swift Playground

Интеллектуальный чат с возможностью выполнения Swift кода для macOS.

## ✨ Функции

- 🤖 **AI чат** - интеллектуальный помощник с поддержкой русского языка
- 🐳 **MCP Docker** - безопасное выполнение Swift кода в Docker контейнерах  
- 🍎 **Native Swift** - быстрое выполнение кода локально (fallback)
- 🔗 **GitHub интеграция** - работа с репозиториями через MCP
- 📱 **macOS дизайн** - нативный интерфейс с NavigationSplitView

## 🏗️ Архитектура

```
macOS App → SwiftExecutionService → MCP Docker (приоритет) / Native Swift (fallback)
```

### Компоненты:

- **MacChatView** - основной интерфейс с двумя панелями
- **SwiftExecutionService** - выбор между MCP Docker и Native Swift
- **MCPDockerService** - HTTP клиент для MCP сервера
- **NativeSwiftExecutor** - локальное выполнение Swift
- **MCP Docker Server** - Flask сервер с Docker интеграцией

## 🚀 Быстрый старт

### 1. Установка зависимостей

```bash
# Убедитесь что установлен Docker Desktop
docker --version

# Установите Python зависимости для MCP (опционально)
cd mcp-docker
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Запуск MCP Docker (опционально)

```bash
cd mcp-docker
source venv/bin/activate
python app.py
```

### 3. Запуск приложения

1. Откройте `AIChat.xcodeproj` в Xcode
2. Выберите схему "AIChatMac"
3. Запустите проект (⌘R)

### 4. Настройка

1. Введите ваш OpenAI API ключ
2. Добавьте GitHub токен (для работы с репозиториями)
3. Начните общение!

## 💻 Использование

### Примеры Swift кода:

```swift
// Простые вычисления
let a = 15
let b = 25
print("Сумма: \(a + b)")

// Функции
func factorial(_ n: Int) -> Int {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}
print("5! = \(factorial(5))")

// Работа с массивами
let numbers = [1, 2, 3, 4, 5]
let doubled = numbers.map { $0 * 2 }
print("Удвоенные: \(doubled)")
```

### GitHub команды:

- "Покажи мои репозитории"
- "Какие Issues в проекте X?"
- "Создай новый репозиторий"

## 🔧 Диагностика

В приложении доступны инструменты диагностики:

- **🔍 Диагностика выполнения** - статус MCP, Native Swift, Sandbox
- **🐳 Диагностика Docker** - подробная проверка Docker

## 📂 Структура проекта

```
AIChat/                    # iOS версия (legacy)
AIChatMac/                 # macOS версия
├── ContentView.swift      # Главный UI
├── MacChatViewModel.swift # ViewModel
├── SwiftExecutionService.swift # Сервис выполнения
├── MCPDockerService.swift # MCP клиент
├── NativeSwiftExecutor.swift # Нативный Swift
├── ExpandingTextEditor.swift # UI компонент
├── DTO/                   # Модели данных
└── Services/              # Общие сервисы

mcp-docker/                # MCP Docker сервер
├── app.py                 # Flask приложение
├── requirements.txt       # Python зависимости
└── docker-compose.yml     # Docker конфигурация

swift-playground/          # Docker образы (legacy)
```

## ⚙️ Настройки

### Entitlements (AIChatMac.entitlements):
- `app-sandbox = false` - отключен sandbox для запуска внешних процессов
- Сетевые разрешения для HTTP запросов к MCP

### Приоритеты выполнения:
1. **MCP Docker** - если доступен (localhost:5002)
2. **Native Swift** - fallback через системный Swift

## 🛠️ Разработка

### Добавление нового языка:

1. Обновите `mcp-docker/app.py` - добавьте endpoint `/execute/{язык}`
2. Создайте новый executor в `AIChatMac/`
3. Обновите `SwiftExecutionService` для выбора исполнителя

### Debugging:

- MCP логи: `mcp-docker/app.py` (Flask debug mode)
- macOS логи: Xcode Console
- Docker логи: `docker logs`

## 📄 Лицензия

MIT License - используйте свободно для любых целей.

---

Создано для демонстрации интеграции AI, Docker и macOS приложений 🚀