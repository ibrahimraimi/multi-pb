const { test, describe, after } = require("node:test");
const assert = require("node:assert");

describe("API Authorization Logic", () => {
  // Simulate the checkAuthorization function logic from server.js
  const checkAuthorization = (authHeader, configuredToken) => {
    // If no admin token is configured (null, undefined, or empty string), allow all requests
    if (!configuredToken || configuredToken === "") {
      return true;
    }
    
    // If admin token is configured, require valid Bearer token
    if (!authHeader) {
      return false;
    }
    
    const token = authHeader.replace(/^Bearer\s+/i, "");
    return token === configuredToken;
  };

  describe("Without admin token configured", () => {
    test("allows all requests when no token is configured (null)", () => {
      assert.strictEqual(checkAuthorization(null, null), true);
      assert.strictEqual(checkAuthorization("Bearer xyz", null), true);
      assert.strictEqual(checkAuthorization("", null), true);
      assert.strictEqual(checkAuthorization(undefined, null), true);
    });

    test("allows all requests when token is empty string", () => {
      assert.strictEqual(checkAuthorization(null, ""), true);
      assert.strictEqual(checkAuthorization("Bearer xyz", ""), true);
      assert.strictEqual(checkAuthorization("", ""), true);
      assert.strictEqual(checkAuthorization(undefined, ""), true);
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

    test("handles tokens with special characters", () => {
      // Token with spaces
      const tokenWithSpaces = "token with spaces";
      assert.strictEqual(
        checkAuthorization("Bearer " + tokenWithSpaces, tokenWithSpaces),
        true
      );

      // Token with special characters
      const specialToken = "token-with_special.chars!@#";
      assert.strictEqual(
        checkAuthorization("Bearer " + specialToken, specialToken),
        true
      );
    });
  });
});


