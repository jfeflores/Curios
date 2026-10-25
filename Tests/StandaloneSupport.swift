// Small compatibility runner for Command Line Tools installations without XCTest.
// The same DomainTests.swift runs under XCTest with `swift test` on a matching Xcode toolchain.
import Foundation

class XCTestCase {}
var failureCount = 0
func XCTFail(_ message: String = "Assertion failed", file: StaticString = #filePath, line: UInt = #line) {
    failureCount += 1; print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: String = "Expected true", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !expression() { XCTFail(message, file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: String = "Expected false", file: StaticString = #filePath, line: UInt = #line) {
    do { if try expression() { XCTFail(message, file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); if a != b { XCTFail("\(a) != \(b) \(message)", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ expression: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if let value = try expression() { XCTFail("Expected nil, got \(value)", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); XCTFail("Expected error", file: file, line: line) } catch {}
}
