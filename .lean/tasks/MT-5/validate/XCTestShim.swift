import Foundation
var xctFailures = 0
class XCTestCase { required init() {} }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { let x=a(), y=b(); if x != y { xctFailures += 1; print("FAIL \(file):\(line) \(x) != \(y)") } }
func XCTAssertEqual<T: BinaryFloatingPoint>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, accuracy: T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { let x=a(), y=b(); if abs(x-y) > accuracy { xctFailures += 1; print("FAIL \(file):\(line) \(x) != \(y)") } }
func XCTAssertTrue(_ a: @autoclosure () -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { if !a() { xctFailures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertFalse(_ a: @autoclosure () -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { if a() { xctFailures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertNil(_ a: @autoclosure () -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { if a() != nil { xctFailures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { if !(a() < b()) { xctFailures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { if !(a() <= b()) { xctFailures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { if !(a() >= b()) { xctFailures += 1; print("FAIL \(file):\(line)") } }
