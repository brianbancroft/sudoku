import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

process.env.SESSION_SECRET ??= "test-session-secret-at-least-32-chars";
process.env.ADMIN_EMAILS ??= "admin@example.com";
process.env.GOOGLE_CLIENT_ID ??= "test-google-client";
process.env.GOOGLE_CLIENT_SECRET ??= "test-google-secret";
process.env.APPLE_SERVICES_ID ??= "com.example.sudoku.signin";
process.env.APPLE_TEAM_ID ??= "TESTTEAMID";
process.env.APPLE_KEY_ID ??= "TESTKEYID";
process.env.APPLE_PRIVATE_KEY ??= "test-only-not-a-real-key";

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
      return {
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            ALLOW_XCODE_JWS: "true",
            SESSION_SECRET: "test-session-secret-at-least-32-chars",
            ADMIN_EMAILS: "admin@example.com",
            PUBLIC_BASE_URL: "https://sudoku-packs.example.workers.dev",
          },
        },
      };
    }),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
