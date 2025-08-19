import Foundation

// Простой тест для проверки что Swift работает
print("Hello from Swift debug test!")

let numbers = [1, 2, 3, 4, 5]
let sum = numbers.reduce(0, +)
print("Sum: \(sum)")

// Функция для тестирования
func greet(_ name: String) -> String {
    return "Hello, \(name)!"
}

print(greet("Docker"))
print("Test completed successfully!")
