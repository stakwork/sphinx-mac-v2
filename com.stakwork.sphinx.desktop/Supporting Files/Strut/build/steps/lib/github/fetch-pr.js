import { z } from "zod";
import { defineStep } from "../../../core.js";
const EXAMPLE = `- id: pr
  type: github/fetch-pr
  config:
    owner: "facebook"
    repo: "react"
    pull_number: 1234
    token: "{{ input.githubToken }}"`;
const limitsSchema = z
    .object({
    maxPatchLines: z.number().int().positive().default(500),
    maxFiles: z.number().int().positive().default(50),
    maxDescriptionChars: z.number().int().positive().default(5000),
    maxCommentChars: z.number().int().positive().default(500),
    maxComments: z.number().int().positive().default(50),
    maxReviews: z.number().int().positive().default(20),
})
    // zod v4: `.default()` now takes a fully-populated OUTPUT value; `.prefault`
    // keeps the v3 behavior of parsing {} so the field defaults apply.
    .prefault({});
export default defineStep({
    type: "github/fetch-pr",
    description: `Fetch a GitHub pull request with files, reviews, comments, and commits, and format it as markdown for LLM consumption. Output: { markdown, pr: { number, title, mergedAt, author, htmlUrl, additions, deletions, changedFiles } }.\n\n${EXAMPLE}`,
    input: z.object({
        owner: z.string().min(1),
        repo: z.string().min(1),
        pull_number: z.number().int().positive(),
        token: z.string().optional(),
        limits: limitsSchema,
    }),
    output: z.object({
        markdown: z.string(),
        pr: z.object({
            number: z.number(),
            title: z.string(),
            mergedAt: z.string().nullable(),
            author: z.string(),
            htmlUrl: z.string(),
            additions: z.number(),
            deletions: z.number(),
            changedFiles: z.number(),
        }),
    }),
    async run(cfg, ctx) {
        // Lazy-load the SDK inside run() so the heavy dep is only pulled into
        // memory when this step actually executes — not at registry-build time.
        // See AGENTS.md "Lib step dependency convention".
        const { Octokit } = await import("@octokit/rest");
        // Credentials flow through the secrets capability (UI-managed store → env
        // fallback) so they're cassette-scrubbed; explicit config always wins.
        // See AGENTS.md "Lib step credentials".
        const auth = cfg.token ?? (await ctx?.services?.secrets?.get("GITHUB_TOKEN"));
        const octokit = new Octokit(auth ? { auth } : {});
        const prInfo = {
            owner: cfg.owner,
            repo: cfg.repo,
            pull_number: cfg.pull_number,
        };
        const [{ data: prData }, { data: files }, { data: reviewComments }, { data: issueComments }, { data: reviews }, { data: commits },] = await Promise.all([
            octokit.pulls.get(prInfo),
            octokit.pulls.listFiles({ ...prInfo, per_page: 100 }),
            octokit.pulls.listReviewComments({ ...prInfo, per_page: 100 }),
            octokit.issues.listComments({
                owner: prInfo.owner,
                repo: prInfo.repo,
                issue_number: prInfo.pull_number,
                per_page: 100,
            }),
            octokit.pulls.listReviews({ ...prInfo, per_page: 100 }),
            octokit.pulls.listCommits({ ...prInfo, per_page: 100 }),
        ]).catch((err) => {
            // GitHub returns 404 both when a PR genuinely doesn't exist AND when
            // the number is an *issue* (issues + PRs share one number sequence) or
            // the repo is private and the token can't see it. Rethrow with an
            // actionable message instead of the bare "Not Found".
            if (err?.status === 404) {
                const ref = `${cfg.owner}/${cfg.repo}#${cfg.pull_number}`;
                throw new Error(`Pull request ${ref} not found. It may be an issue rather than a pull request (issues and PRs share one number sequence), the number may not exist, or the repo may be private and the token lacks access.`);
            }
            throw err;
        });
        const markdown = formatPRContent(prData, files, reviewComments, issueComments, reviews, commits, cfg.limits);
        return {
            markdown,
            pr: {
                number: prData.number,
                title: prData.title,
                mergedAt: prData.merged_at,
                author: prData.user?.login ?? "unknown",
                htmlUrl: prData.html_url,
                additions: prData.additions ?? 0,
                deletions: prData.deletions ?? 0,
                changedFiles: prData.changed_files ?? 0,
            },
        };
    },
});
// ── Formatting helpers (adapted from mcp/src/gitree/pr.ts) ─────────────────
function formatPRContent(prData, files, reviewComments, issueComments, reviews, commits, limits) {
    const sections = [formatHeader(prData)];
    if (typeof prData.body === "string" && prData.body.length > 0) {
        sections.push(formatDescription(prData.body, limits.maxDescriptionChars));
    }
    sections.push(formatFilesChanged(files.slice(0, limits.maxFiles), files.length, limits));
    if (reviewComments.length > 0) {
        sections.push(formatReviewComments(reviewComments.slice(0, limits.maxComments), reviewComments.length, limits.maxCommentChars));
    }
    if (reviews.length > 0) {
        sections.push(formatReviews(reviews.slice(0, limits.maxReviews), reviews.length, limits.maxCommentChars));
    }
    if (issueComments.length > 0) {
        sections.push(formatIssueComments(issueComments.slice(0, limits.maxComments), issueComments.length, limits.maxCommentChars));
    }
    sections.push(formatCommits(commits));
    return sections.join("\n\n");
}
function formatHeader(prData) {
    const user = prData.user;
    const mergedBy = prData.merged_by;
    const base = prData.base;
    const head = prData.head;
    const additions = prData.additions || 0;
    const deletions = prData.deletions || 0;
    const changedFiles = prData.changed_files || 0;
    return `# Pull Request #${prData.number}: ${prData.title}

**Author:** @${user?.login ?? "unknown"}
**Merged by:** ${mergedBy ? `@${mergedBy.login}` : "N/A"}
**Merged at:** ${prData.merged_at ?? "N/A"}
**Base branch:** ${base?.ref ?? "unknown"} → **Head branch:** ${head?.ref ?? "unknown"}
**Changes:** ${changedFiles} files changed, +${additions} -${deletions}
**PR URL:** ${prData.html_url}`;
}
function formatDescription(body, maxChars) {
    const truncated = body.length > maxChars
        ? `${body.substring(0, maxChars)}\n\n... [truncated ${body.length - maxChars} characters]`
        : body;
    return `## Description\n\n${truncated}`;
}
function truncatePatch(patch, maxLines) {
    const lines = patch.split("\n");
    if (lines.length <= maxLines)
        return patch;
    const remaining = lines.length - maxLines;
    return [...lines.slice(0, maxLines), `\n... truncated ${remaining} lines ...`].join("\n");
}
function formatFilesChanged(files, total, limits) {
    const sections = [`## Files Changed (showing ${files.length} of ${total} files)`];
    if (files.length < total) {
        sections.push(`\n*Note: ${total - files.length} files omitted for brevity*\n`);
    }
    for (const file of files) {
        const filename = file.filename ?? "unknown";
        const status = file.status ?? "unknown";
        const additions = file.additions ?? 0;
        const deletions = file.deletions ?? 0;
        const patch = file.patch;
        sections.push(`### ${filename}`);
        sections.push(`**Status:** ${status} | **Changes:** +${additions} -${deletions}`);
        if (patch) {
            sections.push("\n```diff");
            sections.push(truncatePatch(patch, limits.maxPatchLines));
            sections.push("```");
        }
        else {
            sections.push("\n*No patch available (binary file or too large)*");
        }
    }
    return sections.join("\n");
}
function truncate(body, max) {
    return body.length > max ? `${body.substring(0, max)}... [truncated]` : body;
}
function formatReviewComments(comments, total, maxChars) {
    const sections = [`## Code Review Comments (showing ${comments.length} of ${total})`];
    if (comments.length < total) {
        sections.push(`\n*Note: ${total - comments.length} comments omitted for brevity*\n`);
    }
    const byFile = {};
    for (const c of comments) {
        const file = c.path ?? "unknown";
        (byFile[file] ??= []).push(c);
    }
    for (const [file, fileComments] of Object.entries(byFile)) {
        sections.push(`\n### ${file}`);
        for (const comment of fileComments) {
            const line = comment.line ?? comment.original_line ?? "?";
            const author = comment.user?.login ?? "unknown";
            const createdAt = comment.created_at
                ? new Date(comment.created_at).toLocaleString()
                : "unknown";
            const diffHunk = comment.diff_hunk;
            const body = truncate(comment.body ?? "", maxChars);
            sections.push(`\n**@${author}** on line ${line} - ${createdAt}`);
            if (diffHunk) {
                sections.push("```diff");
                sections.push(diffHunk);
                sections.push("```");
            }
            sections.push(`> ${body.replace(/\n/g, "\n> ")}`);
        }
    }
    return sections.join("\n");
}
function formatReviews(reviews, total, maxChars) {
    const sections = [`## Reviews (showing ${reviews.length} of ${total})`];
    if (reviews.length < total) {
        sections.push(`\n*Note: ${total - reviews.length} reviews omitted for brevity*\n`);
    }
    const stateEmoji = {
        APPROVED: "✅",
        CHANGES_REQUESTED: "🔄",
        COMMENTED: "💬",
    };
    for (const review of reviews) {
        const body = review.body;
        const state = review.state ?? "";
        if (!body || state === "COMMENTED")
            continue;
        const reviewer = review.user?.login ?? "unknown";
        const createdAt = review.submitted_at
            ? new Date(review.submitted_at).toLocaleString()
            : "unknown";
        const emoji = stateEmoji[state] ?? "";
        const truncated = truncate(body, maxChars);
        sections.push(`\n${emoji} **@${reviewer}** ${state.toLowerCase().replace("_", " ")} - ${createdAt}`);
        sections.push(`> ${truncated.replace(/\n/g, "\n> ")}`);
    }
    return sections.join("\n");
}
function formatIssueComments(comments, total, maxChars) {
    const sections = [`## Discussion (showing ${comments.length} of ${total})`];
    if (comments.length < total) {
        sections.push(`\n*Note: ${total - comments.length} comments omitted for brevity*\n`);
    }
    for (const comment of comments) {
        const author = comment.user?.login ?? "unknown";
        const createdAt = comment.created_at
            ? new Date(comment.created_at).toLocaleString()
            : "unknown";
        const body = truncate(comment.body ?? "", maxChars);
        sections.push(`\n**@${author}** - ${createdAt}`);
        sections.push(`> ${body.replace(/\n/g, "\n> ")}`);
    }
    return sections.join("\n");
}
function formatCommits(commits) {
    const sections = [`## Commits (${commits.length} commits)`];
    for (const commit of commits) {
        const sha = (commit.sha ?? "").substring(0, 7);
        const data = commit.commit;
        const author = data?.author?.name ?? "unknown";
        const message = (data?.message ?? "").split("\n")[0];
        sections.push(`- \`${sha}\` @${author}: ${message}`);
    }
    return sections.join("\n");
}
//# sourceMappingURL=fetch-pr.js.map