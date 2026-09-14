/**
 * Content hash for a workflow or step version, used purely as an internal
 * **dedup key**: identical content yields the same hash, so re-seeding
 * unchanged templates is a no-op and edited templates are detected. The hash
 * is stored in version metadata — it is NOT the user-facing version id.
 */
export declare function contentHash(content: string): string;
/**
 * Allocate the next sequential, user-facing version label (`v1`, `v2`, …)
 * given the set of existing version ids. Non-`vN` ids are ignored for
 * numbering (but still counted as existing, so labels never collide).
 */
export declare function nextVersionLabel(existing: string[]): string;
