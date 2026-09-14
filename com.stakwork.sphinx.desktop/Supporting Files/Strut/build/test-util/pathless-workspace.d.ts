import { FileWorkspaceStore, type WorkspaceStore } from "../workspace.js";
/** A `WorkspaceStore` that is NOT a `FileWorkspaceStore` and has no `path`:
 *  the file impl's methods bound onto a plain object. It stands in for a
 *  non-file backend, proving nothing reaches through to a directory. */
export declare function pathlessWorkspace(inner: FileWorkspaceStore): WorkspaceStore;
