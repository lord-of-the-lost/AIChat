# AIChat с GitHub MCP интеграцией

iOS приложение для чата с AI агентами с возможностью создания GitHub репозиториев через **настоящий MCP (Model Context Protocol)**.

## 🚀 Что такое MCP?

MCP (Model Context Protocol) - это стандартный протокол для подключения AI моделей к внешним инструментам и данным. В нашем приложении реализована **настоящая MCP интеграция** с GitHub API, которая предоставляет доступ к:

- **Repositories**: создание, управление репозиториями
- **Search**: поиск репозиториев
- **User Info**: получение информации о пользователе
- **Полная интеграция с GitHub API** через MCP протокол

## Возможности

- 💬 Чат с AI агентами (Developer и Reviewer)
- 🚀 Создание GitHub репозиториев через команды в чате
- 🔐 Безопасное хранение API ключей
- 📱 Современный iOS интерфейс

## Настройка

### 1. OpenAI API Key
Получите API ключ на [OpenAI](https://platform.openai.com/api-keys) и введите его в приложении.

### 2. GitHub Personal Access Token
Для создания репозиториев необходимо настроить GitHub токен:

1. Перейдите на [GitHub.com](https://github.com)
2. Settings → Developer settings → Personal access tokens
3. Generate new token (classic)
4. Выберите scope: `repo` (полный доступ к репозиториям)
5. Скопируйте токен и вставьте в приложении

## Использование

### Доступные команды

#### Создание репозитория
- `создай репозиторий my-project`
- `create repository my-project`
- `создай приватный репозиторий my-private-project`
- `create repository my-project с названием Мой новый проект`

#### Создание Issue
- `создай issue в репозитории username/repo с заголовком "Новая функция"`
- `create issue in username/repo titled "Bug fix" with description "Описание бага"`

#### Поиск репозиториев
- `найди репозитории по запросу "machine learning"`
- `search repositories for "react native"`
- `поиск репозиториев "swift ui"`

### Примеры команд

```
создай репозиторий ios-app
создай приватный репозиторий secret-project
create repository web-app с названием Веб приложение
```

## Архитектура

- **ChatService**: Основной сервис для работы с AI агентами
- **GitHubService**: Сервис для работы с GitHub API
- **GitHubAgent**: AI агент для обработки GitHub команд
- **ChatViewModel**: ViewModel для управления состоянием чата

## Технологии

- SwiftUI
- Foundation
- GitHub REST API
- OpenAI API

## Безопасность

- API ключи хранятся в UserDefaults (для продакшена рекомендуется Keychain)
- GitHub токен передается через безопасные HTTPS запросы
- Все API вызовы используют Bearer токены

## Лицензия

MIT License
