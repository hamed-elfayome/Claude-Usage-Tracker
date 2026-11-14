// Minimal XCTest stand-in for Command Line Tools (no Xcode). Compiled with -module-name XCTest.
// Supported API: XCTestCase (setUp/tearDown sync, throwing and async variants, measure,
// addTeardownBlock), XCTFail, XCTAssertEqual (Equatable, accuracy), XCTAssertNotEqual,
// XCTAssertTrue/False, XCTAssertNil/NotNil, XCTAssertLessThan(OrEqual), XCTAssertGreaterThan(OrEqual),
// XCTAssertThrowsError, XCTAssertNoThrow, XCTUnwrap, XCTSkip, XCTSkipUnless, XCTSkipIf.
// Anything else fails to compile: add it here. Re-exports Foundation like the real XCTest.
@_exported import Foundation
nonisolated(unsafe) public var xctFailures = 0
public struct XCTSkip: Error { public let message: String; public init(_ m: String = "") { message = m } }
nonisolated func _fail(_ msg: String, _ file: StaticString, _ line: UInt) { xctFailures += 1; print("    FAIL \(file):\(line) \(msg)") }
open class XCTestCase: NSObject {
  public required override init() { super.init() }
  open func setUp() {} ; open func tearDown() {}
  public func measure(_ block: () -> Void) { block() }
  public var _teardownBlocks: [() -> Void] = []
  public func addTeardownBlock(_ b: @escaping () -> Void) { _teardownBlocks.append(b) }
  open func setUpWithError() throws {} ; open func tearDownWithError() throws {}
  open func setUp() async throws {} ; open func tearDown() async throws {}
}
public func XCTFail(_ m: String = "", file: StaticString = #filePath, line: UInt = #line) { _fail(m, file, line) }
public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { let x = try a(), y = try b(); if x != y { _fail("\(x) != \(y) \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, accuracy: T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { let x = try a(), y = try b(); if abs(x - y) > accuracy { _fail("\(x) != \(y) \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if try a() == b() { _fail("equal \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertTrue(_ a: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if !(try a()) { _fail("not true \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertFalse(_ a: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if try a() { _fail("not false \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertNil(_ a: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if let v = try a() { _fail("not nil: \(v) \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertNotNil(_ a: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if try a() == nil { _fail("nil \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if !(try a() < b()) { _fail("not < \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if !(try a() <= b()) { _fail("not <= \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if !(try a() > b()) { _fail("not > \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { if !(try a() >= b()) { _fail("not >= \(m())", file, line) } } catch { _fail("threw \(error)", file, line) } }
public func XCTAssertThrowsError<T>(_ e: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (_ error: Error) -> Void = { _ in }) { do { _ = try e(); _fail("did not throw \(m())", file, line) } catch { handler(error) } }
public func XCTAssertNoThrow<T>(_ e: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { do { _ = try e() } catch { _fail("threw \(error) \(m())", file, line) } }
public struct XCTUnwrapError: Error {}
public func XCTUnwrap<T>(_ e: @autoclosure () throws -> T?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T { guard let v = try e() else { _fail("unwrap nil \(m())", file, line); throw XCTUnwrapError() }; return v }
public func XCTSkipUnless(_ c: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String? = nil, file: StaticString = #filePath, line: UInt = #line) throws { if !(try c()) { throw XCTSkip(m() ?? "") } }
public func XCTSkipIf(_ c: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String? = nil, file: StaticString = #filePath, line: UInt = #line) throws { if try c() { throw XCTSkip(m() ?? "") } }
public func _xctSyncSetUp(_ t: XCTestCase) throws { try t.setUpWithError(); t.setUp() }
public func _xctSyncTearDown(_ t: XCTestCase) throws { for b in t._teardownBlocks.reversed() { b() }; t._teardownBlocks = []; t.tearDown(); try t.tearDownWithError() }

// Watchdog: aborts the process (exit 3) when one test runs longer than the timeout.
nonisolated(unsafe) var _xctName = ""
nonisolated(unsafe) var _xctStart = 0.0 // ponytail: unlocked, single watcher thread; add a lock if it ever races
public func _xctBegin(_ n: String) { _xctStart = ProcessInfo.processInfo.systemUptime; _xctName = n }
public func _xctEnd() { _xctName = "" }
public func _xctStartWatchdog(_ seconds: Double) {
  setvbuf(stdout, nil, _IOLBF, 0)
  Thread.detachNewThread {
    while true {
      Thread.sleep(forTimeInterval: 0.1)
      let n = _xctName
      if !n.isEmpty && ProcessInfo.processInfo.systemUptime - _xctStart > seconds { print("TIMEOUT \(n)"); fflush(stdout); exit(3) }
    }
  }
}
