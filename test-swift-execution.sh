#!/bin/bash

# Скрипт для тестирования выполнения Swift кода

echo "🚀 Тестируем выполнение Swift кода в Docker"

# Переходим в директорию с Docker конфигурацией
cd swift-playground

# Создаем тестовый Swift файл
cat > main.swift << 'EOF'
import Foundation

print("🚀 Swift Playground тест запущен!")

// Тест 1: Простые вычисления
let a = 15
let b = 25
let sum = a + b
print("Сумма \(a) + \(b) = \(sum)")

// Тест 2: Функция
func multiply(_ x: Int, _ y: Int) -> Int {
    return x * y
}

let result = multiply(7, 8)
print("Произведение 7 × 8 = \(result)")

// Тест 3: Массивы
let numbers = [1, 2, 3, 4, 5]
let squares = numbers.map { $0 * $0 }
print("Квадраты чисел: \(squares)")

print("✅ Тест завершен успешно!")
EOF

echo "📝 Создан тестовый файл main.swift"

# Проверяем, запущен ли Docker
if ! docker --version &> /dev/null; then
    echo "❌ Docker не найден. Пожалуйста, установите Docker Desktop."
    exit 1
fi

echo "✅ Docker найден"

# Загружаем Swift образ если нужно
echo "📦 Проверяем наличие Swift образа..."
if [[ "$(docker images -q swift:5.9 2> /dev/null)" == "" ]]; then
    echo "⬇️ Загружаем Swift образ..."
    docker pull swift:5.9
else
    echo "✅ Swift образ уже доступен"
fi

# Выполняем код
echo "🔥 Выполняем Swift код..."
docker run --rm -v "$(pwd):/app" -w /app swift:5.9 swift main.swift

# Проверяем результат
if [ $? -eq 0 ]; then
    echo "✅ Код выполнен успешно!"
else
    echo "❌ Ошибка выполнения кода"
    exit 1
fi

# Очищаем тестовый файл
rm main.swift

echo "🎉 Тестирование завершено!"
