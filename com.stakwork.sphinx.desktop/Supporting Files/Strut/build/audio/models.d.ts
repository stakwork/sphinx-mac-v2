export interface SttModel {
    id: string;
    url: string;
    /** sha256 of the `.tar.bz2`. */
    sha256: string;
    bytes: number;
    /** Top-level directory inside the archive. */
    archiveDir: string;
    language: string;
    /** How often partials change, measured (ms). Baked into the export. */
    chunkMs: number;
    /** Accepts a hotwords list (`modified_beam_search` transducer). */
    hotwords: boolean;
    /** Emits casing and punctuation. */
    cased: boolean;
    /** Silence to feed after the last audio so the final chunk flushes (ms). */
    tailPadMs: number;
    description: string;
}
export declare const STT_MODELS: readonly SttModel[];
export declare const DEFAULT_MODEL = "zipformer-en-kroko";
export declare const DEFAULT_PARTIAL_MODEL = "nemo-fast-conformer-en-80ms";
export declare function findModel(id: string): SttModel | undefined;
export declare function requireModel(id: string): SttModel;
/** Shared with MiniLM (src/model-dir.ts). STT models live under `<dir>/stt/<id>/`. */
export { modelDirFromEnv } from "../model-dir.js";
export declare function sttModelPath(modelDir: string, id: string): string;
/** Pick the model files inside an extracted dir. Prefers int8 exports. */
export declare function pickModelFiles(entries: readonly string[]): {
    encoder: string;
    decoder: string;
    joiner: string;
    tokens: string;
};
