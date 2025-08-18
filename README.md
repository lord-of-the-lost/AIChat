# AIChat с GitHub и Notion MCP интеграцией

iOS приложение с **универсальным AI ассистентом**, который может обычно общаться и работать с GitHub и Notion через **настоящий MCP (Model Context Protocol)**.

## 🚀 Что такое MCP?

MCP (Model Context Protocol) - это стандартный протокол для подключения AI моделей к внешним инструментам и данным. В нашем приложении реализована **настоящая MCP интеграция** с GitHub API и Notion API, которая предоставляет доступ к:

**GitHub MCP:**
- **User Repositories**: получение списка ваших репозиториев
- **Issues Management**: просмотр и создание Issues в репозиториях  
- **Repository Creation**: создание новых репозиториев
- **Automatic Analysis**: автоматический анализ полученных данных

**Notion MCP:**
- **Page Search**: поиск страниц в Notion workspace
- **Page Content**: получение полного содержимого страниц
- **Cross-Platform Transfer**: перенос данных из Notion в GitHub Issues
- **Smart Integration**: автоматическое форматирование контента

## Возможности

- 💬 **Универсальный AI ассистент** - отвечает на любые вопросы
- 🤖 **Умная GitHub интеграция** - предлагает MCP когда нужно
- 📄 **Notion интеграция** - работает со страницами и содержимым
- 🔄 **Кросс-платформенный перенос** - Notion → GitHub Issues
- 📊 **Автоматический анализ** - анализирует репозитории, Issues и страницы
- 🔐 **Безопасное хранение** API ключей
- 📱 **Современный iOS** интерфейс

## Настройка

### 1. OpenAI API Key
Получите API ключ на [OpenAI](https://platform.openai.com/api-keys) и введите его в приложении.

### 2. GitHub Personal Access Token
Для создания репозиториев и Issues необходимо настроить GitHub токен:

1. Перейдите на [GitHub.com](https://github.com)
2. Settings → Developer settings → Personal access tokens
3. Generate new token (classic)
4. Выберите scope: `repo` (полный доступ к репозиториям)
5. Скопируйте токен и вставьте в приложении

### 3. Notion Integration Token
Для работы с Notion необходимо создать интеграцию:

1. Перейдите на [Notion Integrations](https://www.notion.so/my-integrations)
2. Нажмите "+ New integration"
3. Укажите название и выберите workspace
4. Нажмите "Submit"
5. Скопируйте "Internal Integration Token"
6. Дайте доступ к нужным страницам в Notion (Share → Connect to...)

## Использование

### 🎯 Новый флоу работы

1. **Обычное общение**: Задавайте любые вопросы AI ассистенту
2. **Умное предложение**: При упоминании GitHub/Notion AI предложит MCP
3. **Автоматическое выполнение**: AI сам выберет нужный MCP инструмент
4. **Кросс-платформенная интеграция**: Переносите данные между Notion и GitHub
5. **Анализ результатов**: Автоматический анализ полученных данных

### 💬 Примеры диалогов

**Получение репозиториев:**
```
Вы: "Какие у меня репозитории?"
AI: Хотите использовать MCP для работы с GitHub? Я могу получить список ваших репозиториев.
[AI автоматически вызывает get_user_repositories и анализирует результат]
```

**Просмотр Issues:**
```
Вы: "Покажи Issues в моем проекте MyApp"  
AI: [Автоматически вызывает get_issues и создает план работы]
```

**Поиск в Notion:**
```
Вы: "Найди в Notion страницу проекта ABC"
AI: [Автоматически ищет страницы и показывает результаты]
```

**Перенос Notion → GitHub:**
```
Вы: "Создай GitHub Issue из страницы Notion с ID 12345..."
AI: [Получает содержимое Notion и создает Issue в GitHub]
```

**Обычный разговор:**
```
Вы: "Как работает SwiftUI?"
AI: [Обычный ответ без MCP предложений]
```

### 🛠 Доступные MCP инструменты

**GitHub MCP:**
- **get_user_repositories** - Список ваших репозиториев
- **get_issues** - Issues из конкретного репозитория  
- **create_repository** - Создание нового репозитория
- **create_issue** - Создание нового Issue

**Notion MCP:**
- **search_notion_pages** - Поиск страниц по запросу
- **get_notion_page** - Информация о странице
- **get_notion_page_content** - Полное содержимое страницы
- **create_github_issue_from_notion** - Создание GitHub Issue из Notion

## Архитектура

### 🏗 Простая и понятная структура

- **UniversalAIAgent**: Единый AI ассистент с MCP интеграцией
- **MCPGitHubService**: Сервис для работы с GitHub API через MCP
- **MCPNotionService**: Сервис для работы с Notion API через MCP
- **ChatService**: Простая оболочка для AI агента
- **ChatViewModel**: ViewModel для управления UI

### 🔄 Флоу данных

```
Пользователь → ChatViewModel → ChatService → UniversalAIAgent
                                                     ↓
                    MCP Tools ← MCPGitHubService & MCPNotionService
                         ↓                              ↓
              GitHub API (repos, issues)     Notion API (pages, content)
                         ↓                              ↓
                    Автоматический анализ & Кросс-платформенная интеграция
                                      ↓
                                 Пользователю
```

## Технологии

- SwiftUI
- Foundation
- GitHub REST API
- Notion API
- OpenAI API
- Model Context Protocol (MCP)

## Безопасность

- API ключи хранятся в UserDefaults (для продакшена рекомендуется Keychain)
- GitHub и Notion токены передаются через безопасные HTTPS запросы
- Все API вызовы используют Bearer токены
- Notion интеграция работает только с предоставленными правами доступа

## Лицензия

MIT License
