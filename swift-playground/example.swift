// Пример Swift кода для тестирования

import Foundation

print("🚀 Swift Playground запущен!")

// Пример 1: Простые вычисления
let a = 10
let b = 20
let sum = a + b
print("Сумма \(a) + \(b) = \(sum)")

// Пример 2: Работа со строками
let greeting = "Привет"
let name = "Swift"
let message = "\(greeting), \(name)!"
print(message)

// Пример 3: Массивы и циклы
let numbers = [1, 2, 3, 4, 5]
let doubled = numbers.map { $0 * 2 }
print("Удвоенные числа: \(doubled)")

// Пример 4: Функции
func factorial(_ n: Int) -> Int {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}

print("Факториал 5 = \(factorial(5))")

// Пример 5: Структуры
struct Point {
    let x: Double
    let y: Double
    
    func distance(to other: Point) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

let point1 = Point(x: 0, y: 0)
let point2 = Point(x: 3, y: 4)
print("Расстояние между точками: \(point1.distance(to: point2))")

print("✅ Выполнение завершено успешно!")
