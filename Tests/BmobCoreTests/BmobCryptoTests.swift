import XCTest
@testable import BmobCore

final class BmobCryptoTests: XCTestCase {

    // MARK: - AES Tests

    func testAESEncryptDecryptRoundTrip() throws {
        let plaintext = "Hello, Bmob!"
        let key = "abcdefghijklmnop" // 16 bytes
        let iv = "1234567890abcdef"  // 16 bytes

        guard let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8),
              let plainData = plaintext.data(using: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let encrypted = try BmobCrypto.aesEncrypt(data: plainData, key: keyData, iv: ivData)
        let decrypted = try BmobCrypto.aesDecrypt(data: encrypted, key: keyData, iv: ivData)

        XCTAssertEqual(decrypted, plainData, "Round-trip AES encrypt/decrypt should produce original data")
    }

    func testAESEncryptProducesDifferentOutput() throws {
        let data = "test".data(using: .utf8)!
        let key = "abcdefghijklmnop".data(using: .utf8)!
        let iv = "1234567890abcdef".data(using: .utf8)!

        let encrypted = try BmobCrypto.aesEncrypt(data: data, key: key, iv: iv)
        XCTAssertNotEqual(encrypted, data, "Encrypted data should differ from plaintext")
    }

    func testAESKeyPadding() throws {
        // Key shorter than 16 bytes should be padded
        let data = "test".data(using: .utf8)!
        let shortKey = "short".data(using: .utf8)! // 5 bytes
        let shortIV = "iv".data(using: .utf8)! // 2 bytes

        let encrypted = try BmobCrypto.aesEncrypt(data: data, key: shortKey, iv: shortIV)
        let decrypted = try BmobCrypto.aesDecrypt(data: encrypted, key: shortKey, iv: shortIV)

        XCTAssertEqual(decrypted, data, "Short keys should be padded and still work")
    }

    // MARK: - HMAC-SHA1 Tests

    func testHMACSHA1ProducesOutput() {
        let data = "test".data(using: .utf8)!
        let key = "secret".data(using: .utf8)!

        let result = BmobCrypto.hmacSHA1(data: data, key: key)
        XCTAssertEqual(result.count, 20, "HMAC-SHA1 should produce 20 bytes")
    }

    func testHMACSHA1Deterministic() {
        let data = "test".data(using: .utf8)!
        let key = "secret".data(using: .utf8)!

        let result1 = BmobCrypto.hmacSHA1(data: data, key: key)
        let result2 = BmobCrypto.hmacSHA1(data: data, key: key)

        XCTAssertEqual(result1, result2, "Same input should produce same HMAC")
    }

    // MARK: - Base64 Tests

    func testBase64EncodeReplacesPlus() {
        // 0xFA encodes to base64 chars that include '+'
        let data = Data([0xFA])
        let encoded = BmobCrypto.base64Encode(data)

        XCTAssertFalse(encoded.contains("+"), "Base64 '+' should be replaced with '%2B'")
    }

    func testBase64DecodeRestoresPlus() {
        let original = "test+data"
        guard let originalData = original.data(using: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        let encoded = BmobCrypto.base64Encode(originalData)
        let decoded = BmobCrypto.base64Decode(encoded)

        XCTAssertNotNil(decoded, "Decoded data should not be nil")
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), original)
    }

    func testBase64RoundTrip() {
        let input = "Hello Bmob SDK!"
        let encoded = BmobCrypto.base64EncodeString(input)
        let decoded = BmobCrypto.base64DecodeString(encoded)

        XCTAssertEqual(decoded, input, "Base64 encode/decode round trip should preserve data")
    }

    // MARK: - SHA-256 Tests

    func testSHA256() {
        let result = BmobCrypto.sha256("test")
        XCTAssertEqual(result.count, 64, "SHA-256 hex output should be 64 chars")
        XCTAssertFalse(result.isEmpty, "SHA-256 should not be empty")
    }
}
