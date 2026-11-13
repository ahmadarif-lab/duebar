import XCTest
@testable import DueKit

final class PasswordVerifierTests: XCTestCase {
    func testRightPasswordMatchesAndWrongOnesDoNot() {
        let v = PasswordVerifier.make(password: "correct horse", iterations: 1_000)
        XCTAssertTrue(v.matches("correct horse"))
        XCTAssertFalse(v.matches("correct horse "))
        XCTAssertFalse(v.matches("Correct horse"))
        XCTAssertFalse(v.matches(""))
    }

    func testSaltMakesEveryHashDifferent() {
        let a = PasswordVerifier.make(password: "same", iterations: 1_000)
        let b = PasswordVerifier.make(password: "same", iterations: 1_000)
        XCTAssertNotEqual(a.hash, b.hash)
        XCTAssertNotEqual(a.salt, b.salt)
    }

    func testSurvivesEncodingAndDoesNotContainThePassword() throws {
        let v = PasswordVerifier.make(password: "rahasia123", iterations: 1_000)
        let data = try JSONEncoder().encode(v)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("rahasia123"))
        XCTAssertTrue(try JSONDecoder().decode(PasswordVerifier.self, from: data).matches("rahasia123"))
    }

    func testEmptyPasswordAndUnicode() {
        let empty = PasswordVerifier.make(password: "", iterations: 1_000)
        XCTAssertTrue(empty.matches(""))
        XCTAssertFalse(empty.matches("x"))
        // "é" typed as one character or as e + accent is the same password.
        let v = PasswordVerifier.make(password: "caf\u{e9}", iterations: 1_000)
        XCTAssertTrue(v.matches("cafe\u{301}"))
    }
}
