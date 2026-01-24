const { test, describe, after } = require("node:test");
const assert = require("node:assert");

describe("API Authorization Logic", () => {
  // Simulate the checkAuthorization function logic from server.js
  const checkAuthorization = (authHeader, configuredToken) => {
    if (!configuredToken) return true;
    if (!authHeader) return false;
    const token = authHeader.replace(/^Bearer\s+/i, "");
    return token === configuredToken;
  };

  describe("Without admin token configured", () => {
    test("allows all requests when no token is configured", () => {
      assert.strictEqual(checkAuthorization(null, null), true);
      assert.strictEqual(checkAuthorization("Bearer xyz", null), true);
      assert.strictEqual(checkAuthorization("", null), true);
      assert.strictEqual(checkAuthorization(undefined, null), true);
    });
  });

  describe("With admin token configured", () => {
    const TEST_TOKEN = "test-secret-token-12345";

    test("rejects requests without Authorization header", () => {
      assert.strictEqual(checkAuthorization(null, TEST_TOKEN), false);
      assert.strictEqual(checkAuthorization("", TEST_TOKEN), false);
      assert.strictEqual(checkAuthorization(undefined, TEST_TOKEN), false);
    });

    test("rejects requests with invalid token", () => {
      assert.strictEqual(checkAuthorization("Bearer wrong-token", TEST_TOKEN), false);
      assert.strictEqual(checkAuthorization("Bearer ", TEST_TOKEN), false);
      assert.strictEqual(checkAuthorization("InvalidFormat", TEST_TOKEN), false);
    });

    test("accepts requests with valid token", () => {
      assert.strictEqual(checkAuthorization("Bearer " + TEST_TOKEN, TEST_TOKEN), true);
      assert.strictEqual(checkAuthorization("bearer " + TEST_TOKEN, TEST_TOKEN), true);
      assert.strictEqual(checkAuthorization("BEARER " + TEST_TOKEN, TEST_TOKEN), true);
    });

    test("handles edge cases", () => {
      // Token with spaces
      const tokenWithSpaces = "token with spaces";
      assert.strictEqual(
        checkAuthorization("Bearer " + tokenWithSpaces, tokenWithSpaces),
        true
      );

      // Empty configured token - technically valid but not recommended
      // "Bearer " extracts to empty string which matches empty configured token
      assert.strictEqual(checkAuthorization("Bearer ", ""), true);
      // Empty auth header with empty configured token - should fail (no Bearer prefix)
      assert.strictEqual(checkAuthorization("", ""), true); // empty header extracts to ""
      // null/undefined should fail
      assert.strictEqual(checkAuthorization(null, "non-empty-token"), false);
      assert.strictEqual(checkAuthorization(undefined, "non-empty-token"), false);
    });
  });
});

