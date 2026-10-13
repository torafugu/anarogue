import { defineConfig, loadEnv } from "vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "ANAROGUE_");
  const target = env.ANAROGUE_RUN_API_URL || "http://127.0.0.1:8765";
  return {
    server: { proxy: { "/api": target } },
    preview: { proxy: { "/api": target } },
  };
});
