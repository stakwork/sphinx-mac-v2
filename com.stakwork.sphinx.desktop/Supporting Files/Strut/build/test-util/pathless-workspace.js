import { FileWorkspaceStore } from "../workspace.js";
/** A `WorkspaceStore` that is NOT a `FileWorkspaceStore` and has no `path`:
 *  the file impl's methods bound onto a plain object. It stands in for a
 *  non-file backend, proving nothing reaches through to a directory. */
export function pathlessWorkspace(inner) {
    const out = {};
    for (const k of Object.getOwnPropertyNames(FileWorkspaceStore.prototype)) {
        if (k === "constructor")
            continue;
        const v = inner[k];
        if (typeof v === "function")
            out[k] = v.bind(inner);
    }
    return out;
}
//# sourceMappingURL=pathless-workspace.js.map