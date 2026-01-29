const { test, describe } = require("node:test");
const assert = require("node:assert");
const crypto = require("crypto");

describe("API Authorization Logic", () => {
  // Mirror server.js: constant-time compare when token is set
  const checkAuthorization = (authHeader, configuredToken) => {
    if (!configuredToken) return true;
    if (!authHeader || typeof authHeader !== "string") return false;
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token.length !== configuredToken.length) return false;
    try {
      return crypto.timingSafeEqual(Buffer.from(token, "utf8"), Buffer.from(configuredToken, "utf8"));
    } catch {
      return false;
    }
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

    test("accepts tokens with special characters", () => {
      const specialToken = "token-with_special.chars!@#";
      assert.strictEqual(
        checkAuthorization("Bearer " + specialToken, specialToken),
        true
      );
    });

    test("rejects wrong length token (constant-time safe)", () => {
      assert.strictEqual(checkAuthorization("Bearer x", TEST_TOKEN), false);
      assert.strictEqual(checkAuthorization("Bearer " + TEST_TOKEN + "x", TEST_TOKEN), false);
    });
  });
});


