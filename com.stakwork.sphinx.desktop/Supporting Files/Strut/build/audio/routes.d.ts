/**
 * HTTP surface over the STT service (plans/local-desktop-and-stt.md §4.4).
 * The WebSocket lives in ws.ts. Everything here is gated by `requireApiKey`
 * (permissive in dev, like the rest of strut).
 */
import type { Hono } from "hono";
import { type SttService } from "./stt.js";
export declare function audioRoutes(app: Hono, stt: SttService): void;
