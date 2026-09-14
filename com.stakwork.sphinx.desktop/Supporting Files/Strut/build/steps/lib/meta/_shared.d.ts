import type { AuthoringCapability } from "../../../authoring.js";
/**
 * The `meta/*` steps are thin plumbing over the authoring capability
 * (`services.authoring`, auto-provided by `createStrut`) — the workspace's
 * author/test/inspect operations as REGISTRY STEPS, so an in-workflow agent
 * (`agentTools: ["meta/*"]`) can author, test, and inspect candidate
 * workflows from inside a run. See EVOLVE_SPEC §5.2, and authoring.ts for
 * the ownership rule the capability enforces (§6).
 *
 * GRANT DISCIPLINE (§5.3.2): an authoring agent gets `meta/*` and nothing
 * else — never `bash` alongside it, and never grader steps. The producing
 * agent (the one whose output is graded) gets no `meta/*` at all.
 */
export interface AuthoringServices {
    authoring?: AuthoringCapability;
}
export declare function requireAuthoring(services: unknown): AuthoringCapability;
