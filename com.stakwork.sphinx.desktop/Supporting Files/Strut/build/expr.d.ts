/**
 * Expression evaluator for {{ ... }} templates.
 *
 * Supports:
 *  - Property access: foo.bar.baz, foo["bar"], arr[0]
 *  - Optional chaining: foo?.bar — undefined (no throw) when foo is
 *    null/undefined; guards ONE hop (write a?.b?.c for deeper chains).
 *    The escape hatch for refs into steps a `when:` gate SKIPPED.
 *  - Literals: numbers, strings ('...' or "..."), true, false, null
 *  - Operators: === !== == != < <= > >= && || ! + - * / %
 *  - Ternary: a ? b : c
 *  - Array methods (whitelist): map, filter, find, join, includes, slice —
 *    with single-param arrow lambdas, e.g. {{ search.map(n => n.ref_id) }}.
 *    Expression bodies only (no statements, no user-defined functions), so
 *    every expression still terminates by construction. The whitelist exists
 *    because the language's primary AUTHORS are LLM agents, whose first
 *    attempt is always the JS idiom — grow it only when a real agent misses.
 */
export declare class TemplateError extends Error {
    constructor(message: string);
}
/**
 * Evaluate a single expression string against a scope.
 */
export declare function evaluateExpr(expr: string, scope: Record<string, unknown>): unknown;
/**
 * STATIC analysis for the workflow validator: the scope roots an expression
 * reads (`fetch.body.x` → `fetch`; `items.map(n => n.id)` → `items`, since
 * `n` is lambda-bound). Tokenizes only (a bad character throws
 * `TemplateError`); it does not parse the grammar or evaluate.
 */
export declare function exprRoots(expr: string): string[];
/** Every `{{ expr }}` body in a template string, in order. */
export declare function templateExprs(value: string): string[];
/**
 * Check if a string contains template expressions.
 */
export declare function hasTemplates(value: string): boolean;
/**
 * Resolve a template string. If the entire string is a single `{{ expr }}`,
 * the result preserves the expression's type. Otherwise, segments are
 * stringified and concatenated.
 */
export declare function resolveTemplate(template: string, scope: Record<string, unknown>): unknown;
/**
 * Recursively resolve all template strings in a config object.
 * Returns a deep copy with all templates resolved.
 */
export declare function resolveConfig(config: unknown, scope: Record<string, unknown>): unknown;
